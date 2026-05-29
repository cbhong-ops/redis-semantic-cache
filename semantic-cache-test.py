import time
import os
import google.auth
from langchain_core.globals import set_llm_cache
from langchain_community.cache import RedisSemanticCache
from langchain_google_vertexai import ChatVertexAI, VertexAIEmbeddings

# Set up Google Credentials and Project ID
project_id = os.environ.get("GOOGLE_CLOUD_PROJECT", "your-project-id-here")
credentials, _ = google.auth.default()

# 1. Set up Embedding Model
embeddings = VertexAIEmbeddings(model="text-embedding-004", credentials=credentials, project=project_id)

# 2. Set up Redis Semantic Cache (Connect to local Redis running in Docker)
# score_threshold: Closer to 0 means stricter match (usually 0.1 ~ 0.2 recommended)
redis_url = "redis://localhost:6379"
set_llm_cache(
    RedisSemanticCache(
        redis_url=redis_url,
        embedding=embeddings,
        score_threshold=0.2 
    )
)

# 3. Initialize LLM
llm = ChatVertexAI(model="gemini-2.5-flash", credentials=credentials, project=project_id)

print("--- 첫 번째 질문 (캐시 없음, LLM 직접 호출) ---")
start_time = time.time()
response1 = llm.invoke("where is the capital of Korea?")
print(f"답변: {response1.content.strip()}")
print(f"소요 시간: {time.time() - start_time:.2f}초\n")

print("--- 두 번째 질문 (의미가 유사한 다른 문장, 캐시 적중 예상) ---")
start_time = time.time()
# Sentences are different but meaning is the same, so it returns the cached answer via vector similarity in Redis.
response2 = llm.invoke("let me know where the capital of Korea is")
print(f"답변: {response2.content.strip()}")
print(f"소요 시간: {time.time() - start_time:.2f}초\n")
