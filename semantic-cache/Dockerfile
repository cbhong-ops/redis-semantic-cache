FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Run the web service on container startup.
# Use gunicorn as the production web server.
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
