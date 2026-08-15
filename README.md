# Cloud-Native API (Spec-Driven Learning Project)

Progetto didattico per costruire una pipeline **cloud-native CI/CD end-to-end** su GCP, con focus su:

- Continuous Integration e Continuous Delivery
- Infrastructure as Code (Terraform)
- Security (secrets, IAM, scanning)
- Observability (logging/monitoring)

L'obiettivo non è una business app complessa, ma dimostrare che sai **progettare, rilasciare e operare** un backend in produzione.

## Approccio di lavoro (spec-driven)

Ogni fase viene sviluppata partendo da una spec in `specs/phases/`:

1. **Scope** (cosa implementare)
2. **Acceptance criteria** (definizione oggettiva di completamento)
3. **Evidence** (output verificabili per CV/portfolio)
4. **Decision log** (perché questa scelta e non alternative)

Template: `specs/SPEC_TEMPLATE.md`

## Struttura repository

```text
cloud-native-api/
├── .github/workflows/
├── docs/
├── docker/
├── specs/
├── src/
└── terraform/
```

## Roadmap sintetica

- Phase 0: setup + architettura
- Phase 1: backend API + test
- Phase 2: Docker + compose
- Phase 3-4: CI + quality/security gates
- Phase 5-10: artifact registry + cloud deploy + CD
- Phase 11-13: ambienti, observability, cost

## Avvio locale (stato attuale bootstrap)

Prerequisiti:

- Java 25
- Docker (opzionale per le fasi container)

Comandi:

```bash
./gradlew clean test build
./gradlew bootRun
```

Health endpoint:

```text
GET /actuator/health
```

## Documentazione

- Architettura: `docs/architecture.md`
- Deployment: `docs/deployment.md`
- Security: `docs/security.md`
- Decisioni architetturali: `docs/decisions.md`

## Prime milestone già impostate

- bootstrap Spring Boot + test `contextLoads`
- Gradle Wrapper
- struttura `docs/`, `specs/`, `terraform/`, `.github/workflows/`
- template spec per lavorare fase per fase

## Nota portfolio/CV

Inserisci nel CV solo competenze effettivamente implementate e spiegabili in colloquio, con evidenze concrete (workflow, IaC, diagrammi, runbook, screenshot, log, metriche).
