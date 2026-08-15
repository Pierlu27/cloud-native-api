# Architecture Decision Log

## ADR-001 Cloud Run

**Decisione**: usare Cloud Run come compute layer iniziale.  
**Motivo**: gestione semplificata, autoscaling, focus didattico su CI/CD.

## ADR-002 Cloud SQL

**Decisione**: usare Cloud SQL PostgreSQL.  
**Motivo**: separare compute e data layer, pratica su managed DB.

## ADR-003 Terraform

**Decisione**: provisioning via IaC.  
**Motivo**: riproducibilità, versioning infrastruttura, revisione in PR.

## ADR-004 GitHub Actions

**Decisione**: CI/CD su Actions.  
**Motivo**: integrazione nativa con repository e learning path DevOps.

