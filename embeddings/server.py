import logging
import os
from functools import lru_cache
from typing import List

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

try:
    from llama_cpp import Llama
except ImportError as exc:
    raise RuntimeError(
        "llama-cpp-python is not installed. "
        "Run bin/embedding_server to bootstrap dependencies."
    ) from exc


class EmbeddingRequest(BaseModel):
    inputs: List[str] = Field(default_factory=list)
    truncate: str | None = Field(
        default=None,
        description="Placeholder for compatibility; values other than None are ignored.",
    )


class EmbeddingResponse(BaseModel):
    embeddings: List[List[float]]


logger = logging.getLogger("memcp.embeddings")


@lru_cache(maxsize=1)
def load_model() -> Llama:
    model_path = os.environ.get("MEMORY_EMBEDDING_MODEL_PATH")
    if not model_path or not os.path.exists(model_path):
        raise RuntimeError(
            f"Embedding model not found at '{model_path}'. "
            "Ensure bin/setup_embeddings has been executed."
        )

    threads = int(os.environ.get("MEMORY_EMBEDDING_THREADS", "4"))
    context = int(os.environ.get("MEMORY_EMBEDDING_CONTEXT", "4096"))

    return Llama(
        model_path=model_path,
        embedding=True,
        n_threads=threads,
        n_ctx=context,
        verbose=False,
    )


def create_app() -> FastAPI:
    app = FastAPI(title="MemCP Embedding Service", version="0.1.0")

    @app.on_event("startup")
    async def _load():
        load_model()

    @app.post("/embed", response_model=EmbeddingResponse)
    async def embed(request: EmbeddingRequest) -> EmbeddingResponse:
        if not request.inputs:
            raise HTTPException(status_code=400, detail="inputs cannot be empty")

        llama = load_model()
        target_dim = int(os.environ.get("MEMORY_EMBEDDING_OUTPUT_DIM", "1024"))
        embeddings: List[List[float]] = []

        for text in request.inputs:
            if not text.strip():
                raise HTTPException(status_code=400, detail="input text cannot be blank")

            try:
                result = llama.create_embedding(text)
            except Exception as exc:  # pragma: no cover - logging path
                logger.exception("Embedding generation failed")
                raise HTTPException(status_code=500, detail=str(exc)) from exc

            data = result.get("data")
            if not data:
                logger.error("Embedding response lacked 'data': %s", result)
                raise HTTPException(status_code=500, detail="embedding provider returned empty data")

            vector = data[0].get("embedding")
            if not vector:
                logger.error("Embedding response lacked vector: %s", result)
                raise HTTPException(status_code=500, detail="embedding provider returned empty embedding")

            if target_dim > 0 and len(vector) >= target_dim:
                vector = vector[:target_dim]
            elif target_dim > 0 and len(vector) < target_dim:
                logger.warning(
                    "Embedding vector shorter than target dimension (%s < %s). Padding with zeros.",
                    len(vector),
                    target_dim,
                )
                vector = vector + [0.0] * (target_dim - len(vector))

            if target_dim > 0:
                norm = sum(value * value for value in vector) ** 0.5
                if norm > 0:
                    vector = [value / norm for value in vector]

            embeddings.append(vector)

        return EmbeddingResponse(embeddings=embeddings)

    return app

