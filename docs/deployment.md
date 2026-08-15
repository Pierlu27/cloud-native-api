# Deployment Guide

## Prerequisiti

- progetto GCP
- account con ruoli minimi necessari
- gcloud CLI
- Terraform
- repository GitHub con secrets configurati

## Flusso target

1. Provisioning infrastruttura con Terraform
2. Build + test + scan in CI
3. Build/push immagine su Artifact Registry
4. Deploy su Cloud Run
5. Verifica health endpoint e logs

## Rollback (da completare in Phase 10)

- usare revision precedente di Cloud Run
- mantenere tagging immagine versionato (no solo `latest`)

