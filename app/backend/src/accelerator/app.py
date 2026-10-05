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
    app = Quart(__name__)
    app = cors(app, allow_origin=resolved_settings.allowed_origin)
    app.extensions["settings"] = resolved_settings
    app.extensions["document_processor"] = processor or create_processor(resolved_settings)
    app.register_blueprint(api)

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

