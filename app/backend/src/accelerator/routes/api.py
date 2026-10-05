from typing import cast

from quart import Blueprint, current_app, jsonify, request

from accelerator.config import Settings
from accelerator.errors import ApiError
from accelerator.services.processor import DocumentProcessor

api = Blueprint("api", __name__, url_prefix="/api")


def _processor() -> DocumentProcessor:
    return cast(DocumentProcessor, current_app.extensions["document_processor"])


def _settings() -> Settings:
    return cast(Settings, current_app.extensions["settings"])


@api.get("/health")
async def health():
    return jsonify({"status": "ok"})


@api.get("/capabilities")
async def capabilities():
    settings = _settings()
    return jsonify(
        {
            "mockServices": settings.mock_services,
            "documentIntelligence": bool(settings.document_intelligence_endpoint),
            "search": bool(settings.search_endpoint),
            "foundry": bool(settings.foundry_openai_endpoint),
        }
    )


@api.post("/documents")
async def upload_document():
    files = await request.files
    document = files.get("document")
    if document is None or not document.filename:
        raise ApiError(400, "missing_document", "A PDF document is required.")
    if document.mimetype != "application/pdf":
        raise ApiError(415, "unsupported_media_type", "Only PDF documents are supported.")

    content = document.read()
    if not content:
        raise ApiError(400, "empty_document", "The uploaded document is empty.")
    if len(content) > _settings().maximum_upload_bytes:
        raise ApiError(413, "document_too_large", "The uploaded document exceeds the size limit.")

    job = await _processor().upload(document.filename, content)
    return jsonify(job.to_dict()), 202


@api.post("/jobs/process")
async def process_document():
    payload = await request.get_json(silent=True)
    if not isinstance(payload, dict):
        raise ApiError(400, "invalid_request", "A JSON request body is required.")
    job_id = payload.get("jobId")
    blob_name = payload.get("blobName")
    if not isinstance(job_id, str) or not job_id:
        raise ApiError(400, "invalid_job_id", "jobId is required.")
    if not isinstance(blob_name, str) or not blob_name:
        raise ApiError(400, "invalid_blob_name", "blobName is required.")

    job = await _processor().process(job_id, blob_name)
    return jsonify(job.to_dict())


@api.get("/jobs/<job_id>")
async def get_job(job_id: str):
    job = await _processor().get_job(job_id)
    if job is None:
        raise ApiError(404, "job_not_found", "The requested job was not found.")
    return jsonify(job.to_dict())

