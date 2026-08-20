# Architecture

## Local architecture

```text
Developer machine
   ├─ Spring Boot app
   └─ PostgreSQL (Docker Compose - Phase 2)
```

## Cloud architecture (target)

```text
GitHub Actions -> Artifact Registry -> Cloud Run -> Supabase PostgreSQL
                         |                |
                   Security scans     Runtime environment / Secret Manager (Phase 9)
```

## CI/CD architecture

```text
Push/PR -> CI (build + test + quality/security) -> CD (deploy)
```

## Evidence to collect

- diagram screenshot/versioned source
- workflow run URLs
- deployed service URL + health output

