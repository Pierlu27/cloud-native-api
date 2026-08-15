# Architecture Decision Log

## ADR-001 Cloud Run

**Decision**: use Cloud Run as the initial compute layer.  
**Reason**: simpler operations, autoscaling, learning focus on CI/CD.

## ADR-002 Cloud SQL

**Decision**: use Cloud SQL PostgreSQL.  
**Reason**: separate compute and data layers, practice with a managed DB.

## ADR-003 Terraform

**Decision**: provision infrastructure through IaC.  
**Reason**: reproducibility, infrastructure versioning, PR-based review.

## ADR-004 GitHub Actions

**Decision**: run CI/CD on GitHub Actions.  
**Reason**: native repository integration and DevOps learning path.
