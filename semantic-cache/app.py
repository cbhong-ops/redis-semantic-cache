import time
import os
import google.auth
import redis
import requests
from flask import Flask, request, jsonify, Response, stream_with_context
from google import genai
from google.auth.transport.requests import Request
from langchain_google_vertexai import VertexAIEmbeddings
from langchain_google_memorystore_redis import RedisVectorStore, HNSWConfig, DistanceStrategy

app = Flask(__name__)

# Initialize Google Credentials
credentials, default_project = google.auth.default()
project_id = os.environ.get("GOOGLE_CLOUD_PROJECT", default_project)

# Initialize Embeddings
embeddings = VertexAIEmbeddings(model="text-embedding-004", credentials=credentials, project=project_id)

# Initialize Redis Client and Vector Store
redis_url = os.environ.get("REDIS_URL", "redis://localhost:6379")
redis_client = redis.from_url(redis_url)
# Initialize/Create the vector store index for non-stream
index_config = HNSWConfig(
    name="semantic_cache",
    distance_strategy=DistanceStrategy.COSINE,
    vector_size=768
)
try:
    RedisVectorStore.init_index(client=redis_client, index_config=index_config)
    print("Index 'semantic_cache' initialized successfully.")
except Exception as e:
    print(f"Index initialization failed or already exists: {e}")

# Initialize/Create the vector store index for stream
stream_index_config = HNSWConfig(
    name="semantic_cache_stream",
    distance_strategy=DistanceStrategy.COSINE,
    vector_size=768
)
try:
    RedisVectorStore.init_index(client=redis_client, index_config=stream_index_config)
    print("Index 'semantic_cache_stream' initialized successfully.")
except Exception as e:
    print(f"Index initialization failed or already exists: {e}")

vector_store = RedisVectorStore(
    client=redis_client,
    index_name="semantic_cache",
    embeddings=embeddings
)

vector_store_stream = RedisVectorStore(
    client=redis_client,
    index_name="semantic_cache_stream",
    embeddings=embeddings
)





# Score threshold for semantic cache
score_threshold = float(os.environ.get("SCORE_THRESHOLD", "0.2"))

# Cache TTL in seconds
cache_ttl = int(os.environ.get("CACHE_TTL", "3600"))



def check_cache(prompt, v_store):
    try:
        results = v_store.similarity_search_with_score(prompt, k=1)
        print(f"Search results for '{prompt}': {results}")
        if results:
            doc, score = results[0]
            if score <= score_threshold:
                return doc.metadata.get('response'), score
    except Exception as e:
        print(f"Cache lookup failed: {e}")
    return None, None

@app.route('/v1/projects/<path:path>:generateContent', methods=['POST'])
def generate_content(path):
    # Always use global location as requested
    location = "global"
    
    data = request.get_json()
    
    try:
        prompt = data['contents'][0]['parts'][0]['text']
    except (KeyError, IndexError) as e:
        return jsonify({'error': 'Invalid payload structure'}), 400

    start_time = time.time()
    
    # Check cache
    cached_response, score = check_cache(prompt, vector_store)
    if cached_response:
        duration = time.time() - start_time
        print(f"Cache Hit! Score: {score:.4f}, Duration: {duration:.2f}s")
        
        # Parse it back to JSON to return if it's a string
        import json
        if isinstance(cached_response, str):
            resp = jsonify(json.loads(cached_response))
        else:
            resp = jsonify(cached_response)
        resp.headers['X-Cache'] = 'HIT'
        resp.headers['X-Cache-Score'] = str(score)
        return resp

    # Cache Miss
    print("Cache Miss. Calling Gemini via REST API...")
    try:
        # Get access token
        credentials.refresh(Request())
        token = credentials.token
        
        # Construct Vertex AI REST API URL using request.path
        url = f"https://aiplatform.googleapis.com{request.path}"
        if request.query_string:
            url += f"?{request.query_string.decode('utf-8')}"
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        # Forward the incoming JSON payload directly
        response = requests.post(url, headers=headers, json=data)
        
        if response.status_code != 200:
            print(f"Gemini API call failed with status {response.status_code}: {response.text}")
            return jsonify({'error': 'Gemini API call failed', 'details': response.text}), response.status_code
            
        response_json = response.json()
        
        # Cache the response as JSON string
        import json
        ids = vector_store.add_texts([prompt], metadatas=[{"response": json.dumps(response_json)}])
        for doc_id in ids:
            redis_client.expire(doc_id, cache_ttl)
        
        duration = time.time() - start_time
        print(f"Cache saved. Duration: {duration:.2f}s")
        
        resp = jsonify(response_json)
        resp.headers['X-Cache'] = 'MISS'
        return resp
        
    except Exception as e:
        print(f"Gemini call or caching failed: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/v1/projects/<path:path>:streamGenerateContent', methods=['POST'])
def stream_generate_content(path):
    data = request.get_json()
    
    try:
        prompt = data['contents'][0]['parts'][0]['text']
    except (KeyError, IndexError) as e:
        return jsonify({'error': 'Invalid payload structure'}), 400

    start_time = time.time()
    
    # Check cache
    cached_response, score = check_cache(prompt, vector_store_stream)
    
    if cached_response:
        duration = time.time() - start_time
        print(f"Cache Hit (Stream)! Score: {score:.4f}, Duration: {duration:.2f}s")
        
        import json
        if isinstance(cached_response, str):
            chunks = json.loads(cached_response)
        else:
            chunks = cached_response
        
        def generate_from_cache():
            for chunk in chunks:
                yield chunk + "\n"
                time.sleep(0.01)
                
        resp = Response(stream_with_context(generate_from_cache()), mimetype='text/event-stream')
        resp.headers['X-Cache'] = 'HIT'
        resp.headers['X-Cache-Score'] = str(score)
        return resp

    # Cache Miss
    print("Cache Miss (Stream). Calling Gemini via REST API...")
    try:
        credentials.refresh(Request())
        token = credentials.token
        
        url = f"https://aiplatform.googleapis.com{request.path}"
        if request.query_string:
            url += f"?{request.query_string.decode('utf-8')}"
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        # Call with stream=True
        response = requests.post(url, headers=headers, json=data, stream=True)
        
        if response.status_code != 200:
            print(f"Gemini API call failed with status {response.status_code}: {response.text}")
            return jsonify({'error': 'Gemini API call failed', 'details': response.text}), response.status_code

        def generate_and_cache():
            chunks_accumulated = []
            for line in response.iter_lines():
                if line:
                    decoded_line = line.decode('utf-8')
                    chunks_accumulated.append(decoded_line)
                    yield decoded_line + "\n"
            
            # After stream ends, save to cache
            try:
                import json
                ids = vector_store_stream.add_texts([prompt], metadatas=[{"response": json.dumps(chunks_accumulated)}])
                for doc_id in ids:
                    redis_client.expire(doc_id, cache_ttl)
                print(f"Stream cache saved. Total chunks: {len(chunks_accumulated)}")
            except Exception as e:
                print(f"Failed to save stream to cache: {e}")

        resp = Response(stream_with_context(generate_and_cache()), mimetype='text/event-stream')
        resp.headers['X-Cache'] = 'MISS'
        return resp
        
    except Exception as e:
        print(f"Gemini stream call or caching failed: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/clear', methods=['GET', 'POST'])
def clear_cache():
    try:
        redis_client.flushall()
        
        # Recreate index for non-stream after flush
        index_config = HNSWConfig(
            name="semantic_cache",
            distance_strategy=DistanceStrategy.COSINE,
            vector_size=768
        )
        RedisVectorStore.init_index(client=redis_client, index_config=index_config)

        # Recreate index for stream after flush
        stream_index_config = HNSWConfig(
            name="semantic_cache_stream",
            distance_strategy=DistanceStrategy.COSINE,
            vector_size=768
        )
        RedisVectorStore.init_index(client=redis_client, index_config=stream_index_config)
        
        return jsonify({'message': 'Redis cache cleared and index recreated successfully.'})
    except Exception as e:
        return jsonify({'error': f'Failed to clear cache: {e}'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
