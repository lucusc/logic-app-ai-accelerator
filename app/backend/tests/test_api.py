from io import BytesIO

import pytest
from werkzeug.datastructures import FileStorage

from accelerator.app import create_app
from accelerator.config import Settings
from accelerator.services.processor import MockDocumentProcessor


@pytest.fixture
def app():
    settings = Settings(
        mock_services=True,
        storage_endpoint="",
        submissions_container="documents",
        cosmos_endpoint="",
        cosmos_database="accelerator",
        cosmos_container="jobs",
        document_intelligence_endpoint="",
        search_endpoint="",
        search_index="documents",
        foundry_openai_endpoint="",
        model_deployment="gpt-4.1-mini",
        allowed_origin="http://localhost:5173",
        maximum_upload_bytes=1024,
    )
    return create_app(settings, MockDocumentProcessor())


@pytest.mark.asyncio
async def test_upload_and_process_document(app):
    client = app.test_client()
    upload = await client.post(
        "/api/documents",
        files={
            "document": FileStorage(
                stream=BytesIO(b"%PDF sample"),
                filename="sample.pdf",
                content_type="application/pdf",
            )
        },
    )
    assert upload.status_code == 202
    queued = await upload.get_json()

    process = await client.post(
        "/api/jobs/process",
        json={"jobId": queued["id"], "blobName": queued["file_name"]},
    )
    assert process.status_code == 200
    completed = await process.get_json()
    assert completed["status"] == "completed"
    assert completed["summary"]


@pytest.mark.asyncio
async def test_upload_rejects_non_pdf(app):
    response = await app.test_client().post(
        "/api/documents",
        files={
            "document": FileStorage(
                stream=BytesIO(b"text"),
                filename="sample.txt",
                content_type="text/plain",
            )
        },
    )
    assert response.status_code == 415
    body = await response.get_json()
    assert body["error"]["code"] == "unsupported_media_type"


@pytest.mark.asyncio
async def test_missing_job_returns_not_found(app):
    response = await app.test_client().get("/api/jobs/unknown")
    assert response.status_code == 404
