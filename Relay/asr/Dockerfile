FROM python:3.12-slim AS base
ENV PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1 HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
RUN apt-get update && apt-get install -y --no-install-recommends libsndfile1 libgomp1 curl && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir torch==2.9.1 torchaudio==2.9.1 --index-url https://download.pytorch.org/whl/cu128
RUN pip install --no-cache-dir fastapi==0.135.1 uvicorn==0.41.0 websockets==16.0 soundfile==0.13.1 scipy==1.17.1 python-multipart==0.0.22 jiwer==4.0.0
WORKDIR /app

FROM base AS nemotron
RUN pip install --no-cache-dir transformers==5.17.0 accelerate==1.12.0 librosa==0.11.0
COPY server.py relay_stream.py benchmark.py index.html /app/
ENV ASR_MODEL=nemotron
CMD ["python", "server.py"]

FROM base AS qwen3
RUN pip install --no-cache-dir "qwen-asr[vllm]==0.0.6"
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY server.py relay_stream.py benchmark.py index.html /app/
ENV ASR_MODEL=qwen3 VLLM_WORKER_MULTIPROC_METHOD=spawn VLLM_NO_USAGE_STATS=1 DO_NOT_TRACK=1 GRADIO_ANALYTICS_ENABLED=False
CMD ["python", "server.py"]
