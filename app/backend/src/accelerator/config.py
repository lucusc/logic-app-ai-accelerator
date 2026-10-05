from dataclasses import dataclass
from os import environ


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    mock_services: bool
    storage_endpoint: str
    submissions_container: str
    cosmos_endpoint: str
    cosmos_database: str
    cosmos_container: str
    document_intelligence_endpoint: str
    search_endpoint: str
    search_index: str
    foundry_openai_endpoint: str
    model_deployment: str
    allowed_origin: str
    maximum_upload_bytes: int

    @classmethod
    def from_environment(cls) -> "Settings":
        return cls(
            mock_services=_as_bool(environ.get("ACCELERATOR_MOCK_SERVICES")),
            storage_endpoint=environ.get("AZURE_STORAGE_ENDPOINT", ""),
            submissions_container=environ.get("AZURE_STORAGE_SUBMISSIONS_CONTAINER", "documents"),
            cosmos_endpoint=environ.get("AZURE_COSMOS_ENDPOINT", ""),
            cosmos_database=environ.get("AZURE_COSMOS_DATABASE", "accelerator"),
            cosmos_container=environ.get("AZURE_COSMOS_CONTAINER", "jobs"),
            document_intelligence_endpoint=environ.get(
                "AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT", ""
            ),
            search_endpoint=environ.get("AZURE_SEARCH_ENDPOINT", ""),
            search_index=environ.get("AZURE_SEARCH_INDEX", "documents"),
            foundry_openai_endpoint=environ.get("AZURE_FOUNDRY_OPENAI_ENDPOINT", ""),
            model_deployment=environ.get("AZURE_MODEL_DEPLOYMENT", "gpt-4.1-mini"),
            allowed_origin=environ.get("ALLOWED_ORIGIN", "http://localhost:5173"),
            maximum_upload_bytes=int(environ.get("MAXIMUM_UPLOAD_BYTES", "20971520")),
        )

