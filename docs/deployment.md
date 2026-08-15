# Deployment Guide

## Prerequisites

- GCP project
- account with the minimum required roles
- gcloud CLI
- Terraform
- GitHub repository with configured secrets

## Target flow

1. Infrastructure provisioning with Terraform
2. Build + test + scan in CI
3. Build/push image to Artifact Registry
4. Deploy to Cloud Run
5. Verify health endpoint and logs

## Rollback (to complete in Phase 10)

- use the previous Cloud Run revision
- keep versioned image tags (not only `latest`)
