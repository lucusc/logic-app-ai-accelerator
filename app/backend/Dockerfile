FROM node:20-bookworm-slim AS frontend

WORKDIR /src/app/frontend
COPY app/frontend/package.json app/frontend/package-lock.json ./
RUN npm ci
COPY app/frontend/ ./
RUN npm run build

FROM python:3.12-slim

WORKDIR /app
COPY app/backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/backend/src ./src
COPY --from=frontend /src/app/frontend/dist ./static

ENV PYTHONPATH=/app/src
EXPOSE 8000
CMD ["hypercorn", "--bind", "0.0.0.0:8000", "accelerator.app:create_app()"]
