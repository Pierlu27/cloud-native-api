# Phase 1 verification

This document contains reproducible evidence for the Job API. Start PostgreSQL with
credentials supplied through environment variables, then start the application with
`./gradlew bootRun`.

Set `BASE_URL=http://localhost:8080` and replace `<job-id>` with the identifier
returned by the create request.

## Requests

```bash
curl -i -X POST "$BASE_URL/api/jobs" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Build pipeline","description":"Create the CI pipeline"}'
# 201 Created; response includes status PENDING, id, createdAt and updatedAt.

curl -i "$BASE_URL/api/jobs"
# 200 OK; response is an array of jobs.

curl -i "$BASE_URL/api/jobs/<job-id>"
# 200 OK; response is the requested job.

curl -i -X PUT "$BASE_URL/api/jobs/<job-id>" \
  -H 'Content-Type: application/json' \
  -d '{"status":"RUNNING"}'
# 200 OK; updatedAt is refreshed.

curl -i -X DELETE "$BASE_URL/api/jobs/<job-id>"
# 204 No Content.
```

## Error and OpenAPI checks

```bash
curl -i -X POST "$BASE_URL/api/jobs" \
  -H 'Content-Type: application/json' \
  -d '{"title":"","description":"Create the CI pipeline"}'
# 400 Bad Request with the ApiErrorResponse fields: timestamp, status, error,
# message, path and details.

curl -i "$BASE_URL/api/jobs/00000000-0000-0000-0000-000000000000"
# 404 Not Found with the same ApiErrorResponse shape.

curl -fsS "$BASE_URL/v3/api-docs"
# Includes /api/jobs and /api/jobs/{id}; Swagger UI is at /swagger-ui/index.html.
```

## Automated verification

Run `./gradlew test`. The integration tests use an isolated PostgreSQL 16 Testcontainer,
so Docker must be running. Attach the successful local output and the green GitHub
Actions run to the phase record before marking the Phase 1 checklist complete.
