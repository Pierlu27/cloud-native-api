# Documentation

This folder contains the project documentation used by the spec-driven workflow.

## Contents

- `architecture.md` - target and local architecture overview
- `decisions.md` - architecture decision log
- `deployment.md` - deployment notes
- `local-toolchain-setup.md` - local setup for Terraform and gcloud
- `security.md` - security notes and constraints

## Local setup checklist

For Phase 0, verify the local toolchain before starting implementation work:

1. Java
   ```bash
   java -version
   ```
2. Git
   ```bash
   git --version
   ```
3. Docker
   ```bash
   docker --version
   ```
4. Terraform
   ```bash
   terraform --version
   ```
5. Google Cloud CLI
   ```bash
   gcloud --version
   ```

See `local-toolchain-setup.md` for platform-specific installation guidance.
