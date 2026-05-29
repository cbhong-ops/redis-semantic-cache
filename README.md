# Redis Semantic Cache with Gemini on Cloud Run

This project provides a solution for implementing a semantic cache for LLM (Large Language Model) responses using Redis (Memorystore) and Gemini (Vertex AI), deployed on Cloud Run.

---

## Project Structure

-   **`semantic-cache/`**: Folder containing the Cloud Run application.
    -   **`app.py`**: Flask web application that handles requests and manages the semantic cache.
    -   **`Dockerfile`**: Defines the container image for Cloud Run.
    -   **`requirements.txt`**: Python dependencies.
-   **`semantic-cache-test.py`**: Local test script for verifying the semantic cache concept.
-   **`env.sh`**: Environment variables configuration file.
-   **`deploy-redis.sh`**: Shell script to create Memorystore for Redis (version 7.2+) on GCP.
-   **`deploy-cloudrun.sh`**: Shell script to build and deploy the application to Cloud Run, including setting up firewall rules and service accounts.
-   **`undeploy-all.sh`**: Shell script to clean up all created resources on GCP.
-   **`apiproxy/`**: Apigee API Proxy bundle named `llm-redis-cache-v1` that routes traffic to Cloud Run.

---

## Architecture and Workflow

### 1. Semantic Caching Concept
-   When a user asks a question, the system checks if a similar question has been asked before.
-   It uses **Vertex AI Embeddings** (`text-embedding-004`) to convert the question into a vector.
-   It searches **Memorystore for Redis** (version 7.2+) for the most similar stored vector.
-   If a highly similar question is found (**Cache Hit**), it returns the cached answer, saving cost and time.
-   If no similar question is found (**Cache Miss**), it calls the **Gemini model** (`gemini-2.5-flash`) on Vertex AI, returns the answer, and stores the question-answer pair in Redis for future use.

### 2. Infrastructure
-   **Apigee X**: Acts as the secure API Gateway. Receives client requests and routes them to the Cloud Run backend. (Proxy Name: `llm-redis-cache-v1`)
-   **Cloud Run**: Hosts the Flask app that serves as the backend API and manages the semantic cache logic. (Service Name: `semantic-cache`)
-   **Memorystore for Redis**: Stores the embeddings and cached answers, providing low-latency vector search. (Instance ID: `redis-semantic-cache`)
-   **Vertex AI**: Provides the embedding model and the LLM.
-   **Direct VPC Egress**: Connects Cloud Run to the VPC network where Redis resides without needing a connector.

### 3. Workflow
1.  **Client** calls the Apigee API Proxy.
2.  **Apigee** forwards the request to the **Cloud Run** service.
3.  **Cloud Run** executes the semantic cache logic:
    *   Checks Redis for similar questions.
    *   If found, returns cached answer.
    *   If not found, calls Vertex AI (Gemini), caches the result in Redis, and returns the answer.

---

## Installation and Deployment

### 1. Prerequisites
-   Google Cloud Project with billing enabled.
-   `gcloud` CLI installed and authenticated.
-   Application Default Credentials (ADC) set up:
    ```bash
    gcloud auth application-default login
    ```

### 2. Setup and Deployment

1.  **Configure Environment**: Edit `env.sh` to set your `PROJECT_ID`, `REGION`, and other variables.
    ```bash
    source env.sh
    ```
2.  **Create Redis Instance**: Run the script to create Memorystore for Redis.
    ```bash
    ./deploy-redis.sh
    ```
    *Note: This script creates a Redis 7.2 instance required for vector search.*
3.  **Update Redis IP**: After Redis is created, get its IP address and update `REDIS_IP` in `env.sh`. Then run `source env.sh` again to apply the changes.
4.  **Deploy to Cloud Run**: Run the deployment script. This will also automatically update the Apigee target endpoint with the Cloud Run URL.
    ```bash
    ./deploy-cloudrun.sh
    ```
    *This script will enable required APIs, create a service account with necessary roles, set up a firewall rule, and deploy the app.*
5.  **Deploy Apigee Proxy**: Run the script to upload and deploy the Apigee API Proxy.
    ```bash
    ./deploy-apiproxy.sh
    ```

### 3. Testing

After deployment, use the provided URL to test the service.
-   Access `https://<YOUR_CLOUD_RUN_URL>/test` to run the predefined test cases and verify the cache hit behavior.

### 4. Clearing Cache

If you need to clear the cache (e.g., for testing different endpoints or forcing fresh LLM calls), you can run the following script:
```bash
./clear-redis.sh
```
*Note: This script calls a secure endpoint on Cloud Run to flush Redis and recreate the index. It uses your active Google credentials to authenticate.*

---

## Cleanup

To delete all resources created by this project, run:
```bash
./undeploy-all.sh
```
