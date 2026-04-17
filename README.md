# Recettes fiscales genevoises — Analyse et prévision 2007–2024

**Auteur** : Frat DAG  
**Date** : Avril 2026  
**Données** : OCSTAT T18.02.1.15, OFS Comptes régionaux, BNS data.snb.ch  
**Langage** : R 4.x  

---

## Présentation

Ce projet analyse et prévoit les recettes fiscales cantonales genevoises
sur la période 2007–2024, à partir de données publiques exclusivement.
Il mobilise des outils économétriques standards (ARIMA, ARIMAX, VAR)
complétés par une analyse des drivers via Random Forest et SHAP values.

L'approche est **inductive** : les données posent les questions,
les questions déterminent les tests, les tests déterminent les modèles.
Chaque choix méthodologique est documenté et justifié dans les scripts.

---

## Structure du projet

```
├── 01_exploration.R       # Exploration et statistiques descriptives
├── 02_tests.R             # Tests de stationnarité, ruptures, cointégration
├── 03_modeles.R           # ARIMA, ETS, ARIMAX, VAR
├── 04_shap.R              # Random Forest et analyse SHAP des drivers
├── 04b_walkforward.R      # Validation walk-forward sur les quatre modèles
└── README.md
```

---

## Données

| Source | Série | Période | N |
|--------|-------|---------|---|
| OCSTAT T18.02.1.15 | Recettes fiscales GE (20 postes) | 2007–2024 | 18 |
| OFS Comptes régionaux | PIB nominal Genève | 2008–2022 | 15 |
| BNS data.snb.ch | SARON (mensuel → annuel) | 2007–2024 | 18 |
| OFS via BNS | IPC total suisse (mensuel → annuel) | 2007–2024 | 18 |

**Note nomenclature** : la variable `enreg_timbre` correspond aux
"Produits de l'enregistrement et timbre" dans la nomenclature OCSTAT —
elle agrège les droits de mutation immobiliers, les droits de timbre
et autres droits d'enregistrement. Elle n'est pas équivalente aux seuls
droits de mutation immobiliers.

**Note IR** : à partir de 2012, l'OCSTAT a séparé les impôts à la source
de l'impôt sur le revenu dans sa nomenclature. La baisse apparente de l'IR
sur la période est un artefact comptable. On utilise `pp_total`
(total impôts personnes physiques) comme proxy cohérent sur 2007–2024.

---

## Approche méthodologique

### 1. Exploration (script 01)

Les données sont explorées sans hypothèse préalable sur les modèles.
Les graphiques et statistiques descriptives identifient sept questions
que les données posent — ces questions structurent le script 02.

Observations principales :
- TCAM total 2007–2024 : +2.62%/an
- La croissance est portée par le bénéfice PM (+3.97%/an) et l'IFD
  (+5.18%/an) — pas par l'impôt sur le revenu (-0.49%/an, artefact nomenclature)
- Le bénéfice des personnes morales est le principal vecteur de
  transmission entre l'activité économique genevoise et les recettes
  de l'État (corrélation PIB/ben_pm en différences = 0.82)
- La corrélation SARON/IR passe par le cycle de l'emploi, pas par
  une causalité directe des taux sur les revenus

### 2. Tests statistiques (script 02)

Sept questions traitées dans l'ordre logique — chaque réponse motive la suivante.

**Q7 — Rupture de nomenclature IR** (prérequis à Q1)  
Traité en premier car la comparabilité de la série IR doit être établie
avant tout test de stationnarité. La baisse nominale de l'IR sur
2007–2024 est un artefact comptable lié à la séparation des impôts
à la source en 2012 dans la nomenclature OCSTAT.

**Q1 — Stationnarité** (ADF + PP + KPSS + Zivot-Andrews)  
Triangulation de trois tests pour pallier la faible puissance sur N=18.

| Série | Conclusion |
|-------|-----------|
| Total recettes | I(1) — confirmé trois tests |
| PP total | I(1) — confirmé trois tests |
| Fortune PP | I(1) — confirmé trois tests |
| IFD | I(1) — KPSS confirme malgré ADF ambigu |
| Bénéfice PM | Ambigu — traité comme I(1) (rupture RFFA perturbe les tests) |
| Enreg. et timbre | Ambigu — régresseur potentiel uniquement |

Zivot-Andrews détecte une rupture endogène en position 12 (2018)
pour le total et position 13 (2019) pour le bénéfice PM — cohérent
avec le bond de +8% observé en 2018.

**Q2 — Ruptures structurelles** (test de Chow)

| Année | F-stat | p-value | Conclusion |
|-------|--------|---------|-----------|
| 2010 | 4.197 | 0.037 | Confirmée |
| 2020 | 18.59 | ≈0 | Confirmée |
| 2022 | — | — | Non testable (N=3 post-rupture) |

**Q3 — Outlier successions 2009**  
308M vs médiane 188M (1.7σ). Série exclue de la modélisation principale.

**Q4 — Cointégration** (Johansen)  
Divergence entre test trace (sur-rejette H0) et test valeur propre max
(ne rejette pas H0 à 5%). Par principe de prudence : VAR en différences.

**Q5 — Corrélations en différences**  
Fortune : corrélation 0.86 en niveaux → 0.05 en différences → spurieuse,
exclue des régresseurs. Ben_pm, IFD, PIB : corrélations persistantes → réelles.

**Q6 — Dummies**  
dummy_rffa (+1729M, p≈0) : intégrée dans tous les modèles.  
dummy_covid (p=0.61) : exclue — Genève n'a pas subi de rupture fiscale
en 2020, ce qui témoigne de la résilience de son tissu économique.

### 3. Modèles (script 03)

Quatre modèles construits par complexité croissante,
chaque modèle motivé par les résultats du précédent.

| Modèle | RMSE training | Ljung-Box p | Statut |
|--------|--------------|-------------|--------|
| ARIMA(0,1,0) + drift | 391M | 0.613 | Baseline |
| ETS(M,N,N) | 434M | 0.683 | Inférieur à ARIMA |
| **ARIMAX(0,1,0) + dummy_rffa** | **283M** | **0.748** | **Retenu** |
| VAR(1) en différences | — | — | Exploratoire |

**Modèle retenu : ARIMAX(0,1,0) + dummy_rffa**  
Amélioration de 27.7% vs ARIMA baseline.  
Coefficient dummy_rffa = +1398M (p≈0).

**Prévisions 2025–2027 :**

| Année | Point forecast | IC 80% | IC 95% |
|-------|---------------|--------|--------|
| 2025 | 9'269M | [8'885 – 9'653] | [8'681 – 9'857] |
| 2026 | 9'269M | [8'726 – 9'812] | [8'438 – 10'100] |
| 2027 | 9'269M | [8'604 – 9'934] | [8'251 – 10'287] |

Le plateau à 9'269M reflète la structure du modèle ARIMA(0,1,0)
avec dummy_rffa constante à 1 pour les années futures.
Les prévisions sont à interpréter comme un scénario central de
stabilisation post-RFFA, pas comme une trajectoire de croissance.

### 4. Analyse SHAP des drivers (script 04)

Le Random Forest est utilisé **uniquement pour l'analyse des drivers**,
pas pour la prévision. RMSE test 2022–2024 = 1978M — la sous-prédiction
est attendue et documentée : le modèle n'a pas vu les niveaux
exceptionnels de la RFFA pendant l'entraînement.

**Classement SHAP (contribution moyenne absolue) :**

| Rang | Variable | SHAP moyen |
|------|----------|-----------|
| 1 | Recettes fiscales (t-1) | 120M |
| 2 | Tendance temporelle | 112M |
| 3 | Recettes fiscales (t-2) | 85M |
| 4 | Part IFD (t-1) | 63M |
| 5 | Taux SARON (t-1) | 50M |
| 6 | Bénéfice PM (t-1) | 28M |
| 7 | Inflation IPC (t-1) | 5M |
| 8 | Effet RFFA 2022+ | 0M* |

*dummy_rffa = 0 pour toutes les observations du training (2009–2021).
Le RF ne peut pas apprendre un effet qu'il n'a jamais vu. L'effet RFFA
est capturé par l'ARIMAX (+1398M, p≈0), pas par le RF.

Note : l'IFD devance le bénéfice PM en importance SHAP (63M vs 28M).
L'IFD capte indirectement l'effet RFFA via la redistribution fédérale
des impôts sur les bénéfices des grandes entreprises genevoises.

Les classements RF classique (%IncMSE) et SHAP sont cohérents —
robustesse de la conclusion confirmée.

### 5. Validation walk-forward (script 04b)

Validation sur base équitable : entraînement sur 2007:(t-1),
prédiction de t, pour t = 2017 à 2024.

**Prédictions vs réalisations — année par année :**

| Année | Réalisé | ARIMA | ETS | ARIMAX | RF |
|-------|---------|-------|-----|--------|----|
| 2017 | 6'641M | 6'590M | 6'496M | n/a | 6'434M |
| 2018 | 7'173M | 6'708M | 6'585M | n/a | 6'499M |
| 2019 | 7'363M | 7'282M | 7'022M | n/a | 6'909M |
| 2020 | 7'454M | 7'479M | 7'350M | n/a | 6'999M |
| 2021 | 7'871M | 7'568M | 7'454M | n/a | 7'078M |
| 2022 | 9'269M | 8'007M | 7'871M | n/a | 7'530M |
| 2023 | 9'734M | 9'489M | 9'269M | 9'269M | 8'555M |
| 2024 | 9'269M | 9'969M | 9'734M | 9'734M | 9'150M |

**RMSE walk-forward — toutes années (2017–2024) :**

| Modèle | RMSE | Note |
|--------|------|------|
| ARIMAX | 465M | Non estimable avant 2022† |
| ARIMA baseline | 555M | |
| ETS | 618M | |
| Random Forest | 864M | |

**RMSE walk-forward — hors RFFA (2017–2021) :**

| Modèle | RMSE |
|--------|------|
| ARIMA baseline | 252M |
| ETS | 365M |
| Random Forest | 555M |
| ARIMAX | exclu† |

†ARIMAX non estimable avant 2022 : dummy_rffa = 0 sur tout
l'entraînement ET le test pour 2017–2021 — le modèle est identique
à ARIMA pur sur cette fenêtre.

ARIMA est le meilleur modèle en conditions normales (252M hors RFFA).
ARIMAX capture mieux les ruptures structurelles connues (465M toutes
années). Ces deux résultats sont complémentaires.

---

## Encadré RFFA

La Réforme fiscale et financement de l'AVS (RFFA), entrée en vigueur
le 1er janvier 2020, a supprimé les régimes fiscaux préférentiels cantonaux
et les a remplacés par des instruments conformes aux standards OCDE
(patent box, déductions R&D).

La rupture observable en 2022–2023 dans les recettes genevoises résulte
de plusieurs facteurs concomitants : délai de transition entre les deux
régimes, bénéfices exceptionnels post-COVID dans les secteurs du négoce
de matières premières, de la pharmacie et de la finance — secteurs
surreprésentés à Genève (Trafigura, Vitol, Gunvor, Roche, Novartis).

L'effet RFFA est partiellement quantifiable (+1398M via ARIMAX)
mais non décomposable sans données désagrégées par type de contribuable.
Il est traité ici comme un choc structurel documenté, pas comme
une tendance durable.

Sources : AFC (estv.admin.ch), ge.ch, OCDE Pilier 2, OCSTAT.

---

## Limitations

Ce projet documente ses limites de manière explicite — l'honnêteté
méthodologique est une exigence, pas une option.

**Taille de l'échantillon**  
N=18 observations annuelles. La puissance des tests statistiques
est faible. Les conclusions sont des hypothèses de travail validées
par triangulation, pas des verdicts définitifs.

**Données annuelles**  
Contrainte imposée par la source OCSTAT — pas un choix. Des données
trimestrielles ou mensuelles permettraient des tests plus robustes.

**Effet RFFA non décomposé**  
La dummy_rffa capture un effet global. La décomposition entre
effet RFFA pur, effet cycle économique et effets sectoriels
nécessiterait des données désagrégées non disponibles publiquement.

**SHAP values instables**  
N=13 en training pour le Random Forest. Les SHAP values sont
présentées comme indicateurs de direction, pas comme mesures précises.

**Fenêtre de prévision limitée**  
Les prévisions 2025–2027 reposent sur l'hypothèse de persistance
de l'effet RFFA (dummy = 1). Si les bénéfices des grandes entreprises
genevoises se normalisent, les recettes pourraient converger vers
la tendance pré-RFFA plus rapidement que prévu.

**PIB disponible jusqu'en 2022 seulement**  
Les comptes régionaux OFS sont publiés avec un délai de 2–3 ans.
Le PIB genevois n'est pas utilisé comme régresseur dans les modèles
de prévision pour cette raison.

---

## Reproductibilité

Les scripts doivent être exécutés dans l'ordre :

```r
source("01_exploration.R")
source("02_tests.R")
source("03_modeles.R")
source("04_shap.R")
source("04b_walkforward.R")
```

Chaque script vérifie la présence de l'objet `df` en mémoire
et s'arrête avec un message explicite si les scripts précédents
n'ont pas été exécutés.

**Packages requis :**
```r
install.packages(c("tidyverse", "tseries", "urca", "strucchange",
                   "forecast", "vars", "randomForest", "fastshap",
                   "ggplot2", "patchwork", "scales"))
```

**Seed** : `set.seed(42)` dans tous les blocs avec aléatoire.

---

## Contact

**Frat DAG**  
Email : fratdag@gmail.com  
LinkedIn : https://www.linkedin.com/in/fratdag/
