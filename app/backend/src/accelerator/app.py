from pathlib import Path

from quart import Quart, jsonify
from quart_cors import cors

from accelerator.config import Settings
from accelerator.errors import ApiError
from accelerator.routes.api import api
from accelerator.services.processor import DocumentProcessor, create_processor


def create_app(
    settings: Settings | None = None,
    processor: DocumentProcessor | None = None,
) -> Quart:
    resolved_settings = settings or Settings.from_environment()
    static_directory = Path(__file__).resolve().parents[2] / "static"
    app = Quart(__name__, static_folder=str(static_directory), static_url_path="")
    app = cors(app, allow_origin=resolved_settings.allowed_origin)
    app.extensions["settings"] = resolved_settings
    app.extensions["document_processor"] = processor or create_processor(resolved_settings)
    app.register_blueprint(api)

    @app.get("/")
    async def serve_frontend():
        return await app.send_static_file("index.html")

    @app.get("/<path:path>")
    async def serve_frontend_path(path: str):
        candidate = (static_directory / path).resolve()
        if static_directory.resolve() in candidate.parents and candidate.is_file():
            return await app.send_static_file(path)
        return await app.send_static_file("index.html")

    @app.errorhandler(ApiError)
    async def handle_api_error(error: ApiError):
        return (
            jsonify({"error": {"code": error.code, "message": error.message}}),
            error.status_code,
        )

    @app.errorhandler(Exception)
    async def handle_unexpected_error(error: Exception):
        app.logger.exception("Unhandled request error", exc_info=error)
        return (
            jsonify(
                {
                    "error": {
                        "code": "internal_error",
                        "message": "The request could not be completed.",
                    }
                }
            ),
            500,
        )

    return app
