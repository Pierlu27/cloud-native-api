# Security Notes

## Principi

- least privilege su IAM
- niente secrets nel repository
- scansioni automatiche in CI

## Controlli previsti

- dependency scanning
- secret scanning
- container image scanning

## Evidenze

- report scan allegati ai workflow
- elenco ruoli IAM assegnati
- decisioni documentate in `docs/decisions.md`

