[![CI](https://github.com/fatou5/Projet_DevOps/actions/workflows/tests.yml/badge.svg)](https://github.com/fatou5/Projet_DevOps/actions/workflows/tests.yml)

## CI

Le pipeline GitHub Actions se déclenche sur les Pull Requests et sur les
pushs vers `main`. Il exécute un job de lint avec Flake8 puis les tests
avec pytest sur Python 3.10, 3.11 et 3.12. Les dépendances pip sont
mises en cache et les rapports de couverture HTML sont conservés comme
artefacts.

# Git Workshop


Projet réalisé dans le cadre de l'atelier Git et DevOps.

Projet réalisé dans le cadre d'un atelier de développement et DevOps.



## Stratégie Git

Ce projet utilise une stratégie **Trunk-Based Development**.

### Branche principale

La branche principale est :

- `main`

### Convention de nommage

Les nouvelles fonctionnalités sont développées dans des branches :

```text
feature/<nom-de-la-fonctionnalite>

Correction urgente appliquée dans le cadre de l'incident.
Commit signing configured with SSH.
