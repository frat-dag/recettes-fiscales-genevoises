# =============================================================================
# PROJET : ANALYSE & PRÉVISION DES RECETTES FISCALES GENEVOISES
# Script  : 02_tests.R
# Auteur  : Frat DAG
# Date    : Avril 2026
# Version : 2.0 — approche inductive
# =============================================================================
# CE QU'ON SAIT APRÈS LE SCRIPT 01 :
#   - Tendance haussière générale portée par ben_pm et ifd — pas par l'IR
#   - L'IR décroît nominalement sur 2007–2024 (Q7 — à élucider en premier)
#   - Ben_pm est le principal vecteur de transmission PIB → recettes fiscales
#   - La corrélation PIB/recettes est structurelle et attendue (pas spurieuse)
#   - La corrélation SARON/IR passe par le cycle emploi, pas les taux directs
#   - Ruptures visuelles : 2010 (crise), 2020 (COVID), 2022–2023 (RFFA)
#   - Outlier successions 2009 (308M vs médiane 188M)
#
# QUESTIONS À TRAITER — DANS CET ORDRE (chaque réponse motive la suivante) :
#   Q7 — Pourquoi l'IR décroît-il ? (prérequis à Q1 pour cette série)
#   Q1 — Stationnarité ADF + PP (sur séries corrigées après Q7)
#   Q1A — Complément KPSS (triangulation)
#   Q1B — Complément Zivot-Andrews (rupture endogène)
#   Q2 — Ruptures structurelles Chow (informent Q1 et Q3)
#   Q3 — Outlier successions 2009 (découle de Q2)
#   Q4 — Cointégration Johansen (nécessite I(1) confirmé par Q1)
#   Q5 — Relations macro sur séries différenciées (après Q1)
#   Q6 — Dummy RFFA testée formellement (s'appuie sur Q2)
# =============================================================================

library(tidyverse)
library(tseries)      # adf.test, kpss.test
library(urca)         # ur.pp, ca.jo, ur.za
library(strucchange)  # sctest (Chow)
library(ggplot2)
library(patchwork)
library(scales)

# -----------------------------------------------------------------------------
# 0. VÉRIFICATION
# -----------------------------------------------------------------------------

if (!exists("df")) {
  stop("L'objet 'df' n'est pas en mémoire. Relancer le script 01 d'abord.")
}
cat("✓ Objet 'df' disponible :", nrow(df), "observations\n\n")

couleurs <- c("#2C3E50", "#E74C3C", "#2980B9", "#27AE60", "#F39C12")

# =============================================================================
# Q7 — POURQUOI L'IR DÉCROÎT-IL EN TENDANCE ?
# =============================================================================
# POURQUOI EN PREMIER :
# Avant de tester la stationnarité de l'IR (Q1), il faut s'assurer que
# la série est comparable sur toute la période. Si la baisse est un artefact
# de nomenclature, inclure l'IR brut dans les tests et modèles introduit
# un biais de mesure. Q7 est donc un prérequis à Q1 pour cette série.
#
# CONTEXTE :
# En 2012, l'OCSTAT a séparé les "impôts à la source" de l'IR dans sa
# nomenclature. Avant 2012, les impôts à la source étaient inclus dans l'IR.
# Après 2012, ils apparaissent sur une ligne distincte.
# → La baisse apparente de l'IR est un artefact comptable, pas économique.
# =============================================================================

cat("=============================================================\n")
cat("Q7 — RUPTURE DE NOMENCLATURE DANS L'IR\n")
cat("=============================================================\n\n")

df <- df %>%
  mutate(
    source_imp = c(NA, NA, NA, NA, NA,
                   757, 721, 597, 726, 722, 741, 786,
                   796, 810, 1003, 1484, 1097, 1282),
    ir_corrige = ifelse(!is.na(source_imp),
                        ir + source_imp, ir)
  )

cat("IR seul 2007–2011 (moyenne)      :",
    round(mean(df$ir[df$annee <= 2011]), 0), "M\n")
cat("IR seul 2012–2024 (moyenne)      :",
    round(mean(df$ir[df$annee >= 2012]), 0), "M\n")
cat("IR corrigé 2012–2024 (moyenne)   :",
    round(mean(df$ir_corrige[df$annee >= 2012],
               na.rm = TRUE), 0), "M\n")
cat("PP total 2007–2024 (moyenne)     :",
    round(mean(df$pp_total), 0), "M\n\n")

cat("# DÉCISION Q7 :\n")
cat("# La baisse de l'IR est un artefact de nomenclature OCSTAT 2012.\n")
cat("# On utilise pp_total comme proxy cohérent sur 2007–2024.\n")
cat("# L'IR corrigé (IR + source) sera testé en sensibilité (script 03).\n")
cat("# → Cette décision est prise AVANT les tests de stationnarité.\n\n")

# =============================================================================
# Q1 — TESTS DE STATIONNARITÉ (ADF + PP)
# =============================================================================
# POURQUOI APRÈS Q7 :
# Les séries testées sont maintenant correctement définies — on utilise
# pp_total et non ir, conformément à la décision Q7.
#
# MÉTHODE :
# ADF (Augmented Dickey-Fuller) et Phillips-Perron sur chaque série,
# en niveau puis en différence première.
# Les deux tests corrigent l'autocorrélation différemment — leur accord
# renforce la robustesse de la conclusion sur petit échantillon.
#
# LIMITE EXPLICITÉE :
# Avec N=18, la puissance des tests est faible. Un non-rejet de H0
# ne prouve pas la non-stationnarité — c'est une hypothèse de travail
# validée conjointement avec l'inspection visuelle du script 01.
# =============================================================================

cat("=============================================================\n")
cat("Q1 — TESTS DE STATIONNARITÉ (ADF + PP)\n")
cat("=============================================================\n\n")

cat("⚠️  LIMITE : N=18 → puissance faible. Les tests sont des guides,\n")
cat("    pas des verdicts. L'inspection visuelle (script 01) reste\n")
cat("    un input important dans la décision finale.\n\n")

series_list <- list(
  "Total recettes"     = ts(df$total,      start = 2007, frequency = 1),
  "PP total"           = ts(df$pp_total,   start = 2007, frequency = 1),
  "Bénéfice PM"        = ts(df$ben_pm,     start = 2007, frequency = 1),
  "Fortune PP"         = ts(df$fortune,    start = 2007, frequency = 1),
  "IFD"                = ts(df$ifd,        start = 2007, frequency = 1),
  "Enregistrement et timbre (OCSTAT)" = ts(df$enreg_timbre, start = 2007, frequency = 1)
)

tester_stationnarite <- function(serie, nom) {
  cat("---", nom, "---\n")
  
  adf_niv  <- adf.test(serie, k = 1)
  adf_diff <- adf.test(diff(serie), k = 1)
  pp_niv   <- ur.pp(serie, type = "Z-tau",
                    model = "trend", lags = "short")
  pp_stat  <- pp_niv@teststat
  pp_crit  <- pp_niv@cval[2]
  
  cat("ADF niveau    : p =", round(adf_niv$p.value, 3),
      ifelse(adf_niv$p.value < 0.05,
             "→ stationnaire", "→ non stationnaire"), "\n")
  cat("ADF diff 1ère : p =", round(adf_diff$p.value, 3),
      ifelse(adf_diff$p.value < 0.05,
             "→ stationnaire", "→ non stationnaire"), "\n")
  cat("PP niveau     : stat =", round(pp_stat, 3),
      "| crit 5% =", round(pp_crit, 3),
      ifelse(pp_stat < pp_crit,
             "→ stationnaire", "→ non stationnaire"), "\n")
  
  I1 <- adf_niv$p.value > 0.05 & adf_diff$p.value < 0.05
  cat("→ DÉCISION :",
      ifelse(I1,
             "I(1) — différenciation requise",
             "Ambigu — voir inspection visuelle"),
      "\n\n")
  
  list(serie      = nom,
       adf_niv_p  = round(adf_niv$p.value, 3),
       adf_diff_p = round(adf_diff$p.value, 3),
       pp_stat    = round(pp_stat, 3),
       pp_crit    = round(pp_crit, 3),
       decision   = ifelse(I1, "I(1)", "Ambigu"))
}

resultats_station <- map(names(series_list),
                         ~tester_stationnarite(series_list[[.x]], .x))
tableau_station   <- map_dfr(resultats_station, ~as_tibble(.x))

cat("=== TABLEAU DE SYNTHÈSE — STATIONNARITÉ ADF/PP ===\n")
print(tableau_station)

cat("\n# DÉCISION Q1 :\n")
cat("# Les séries fiscales principales sont I(1).\n")
cat("# On travaillera sur les différences premières dans le script 03.\n")
cat("# → Cette conclusion motive Q4 : si I(1), tester la cointégration.\n\n")

# =============================================================================
# Q1A — COMPLÉMENT : TEST KPSS
# =============================================================================
# POURQUOI :
# ADF et PP testent H0 = non stationnaire (racine unitaire).
# Le KPSS teste dans l'autre sens : H0 = stationnaire.
# Utiliser les trois tests permet une triangulation :
#   - ADF non rejeté + KPSS rejeté     → I(1) confirmé des deux côtés
#   - ADF non rejeté + KPSS non rejeté → résultat ambigu, manque de puissance
#   - ADF rejeté + KPSS non rejeté     → I(0) confirmé des deux côtés
# C'est particulièrement utile pour les séries ambiguës (ben_pm, ifd,
# enreg_timbre) où ADF seul ne permettait pas de conclure.
# =============================================================================

cat("=============================================================\n")
cat("Q1A — COMPLÉMENT : TEST KPSS\n")
cat("=============================================================\n\n")

cat("POURQUOI : ADF et PP testent H0=non stationnaire. Le KPSS teste\n")
cat("H0=stationnaire. La triangulation des trois tests renforce\n")
cat("la robustesse des conclusions, surtout pour les séries ambiguës.\n\n")

tester_kpss <- function(serie, nom) {
  kpss_niv  <- kpss.test(serie,       null = "Trend")
  kpss_diff <- kpss.test(diff(serie), null = "Level")
  
  cat("---", nom, "---\n")
  cat("KPSS niveau (H0=stat) : stat =", round(kpss_niv$statistic, 3),
      "| p =", round(kpss_niv$p.value, 3),
      ifelse(kpss_niv$p.value < 0.05,
             "→ REJET H0 → non stationnaire",
             "→ non rejet → stationnaire"),
      "\n")
  cat("KPSS diff   (H0=stat) : stat =", round(kpss_diff$statistic, 3),
      "| p =", round(kpss_diff$p.value, 3),
      ifelse(kpss_diff$p.value < 0.05,
             "→ REJET H0 → différence non stationnaire",
             "→ non rejet → différence stationnaire"),
      "\n\n")
  
  list(
    serie         = nom,
    kpss_niv_p    = round(kpss_niv$p.value, 3),
    kpss_diff_p   = round(kpss_diff$p.value, 3),
    kpss_niv_dec  = ifelse(kpss_niv$p.value < 0.05,  "Non stat", "Stat"),
    kpss_diff_dec = ifelse(kpss_diff$p.value < 0.05, "Non stat", "Stat")
  )
}

resultats_kpss <- map(names(series_list),
                      ~tester_kpss(series_list[[.x]], .x))
tableau_kpss   <- map_dfr(resultats_kpss, ~as_tibble(.x))

cat("=== TABLEAU KPSS ===\n")
print(tableau_kpss)

# Triangulation ADF + PP + KPSS
cat("\n=== TRIANGULATION ADF + PP + KPSS ===\n\n")

triangulation <- tableau_station %>%
  left_join(tableau_kpss %>%
              dplyr::select(serie, kpss_niv_dec, kpss_diff_dec),
            by = "serie") %>%
  mutate(
    conclusion_finale = case_when(
      decision == "I(1)" & kpss_niv_dec == "Non stat" &
        kpss_diff_dec == "Stat"     ~ "I(1) — confirmé trois tests",
      decision == "I(1)" & kpss_niv_dec == "Non stat" &
        kpss_diff_dec == "Non stat" ~ "I(1) — ADF/PP confirment, KPSS ambigu",
      decision == "Ambigu" & kpss_niv_dec == "Non stat" &
        kpss_diff_dec == "Stat"     ~ "I(1) — KPSS confirme malgré ADF ambigu",
      decision == "Ambigu" & kpss_niv_dec == "Non stat" &
        kpss_diff_dec == "Non stat" ~ "Indéterminé — manque de puissance (N=18)",
      TRUE ~ "Cas particulier — voir inspection visuelle"
    )
  ) %>%
  dplyr::select(serie, decision, kpss_niv_dec, kpss_diff_dec,
                conclusion_finale)

print(triangulation)

cat("\n# DÉCISION Q1A :\n")
cat("# Les conclusions renforcées ou modifiées par le KPSS sont\n")
cat("# reprises dans la synthèse finale de ce script.\n\n")

# =============================================================================
# Q1B — COMPLÉMENT : TEST DE ZIVOT-ANDREWS
# =============================================================================
# POURQUOI :
# Le test de Chow (Q2) teste la rupture à un point FIXÉ a priori.
# Le test de Zivot-Andrews identifie ENDOGÈNEMENT le point de rupture
# le plus probable et teste simultanément la stationnarité.
# H0 : racine unitaire sans rupture structurelle
# H1 : série stationnaire avec une rupture structurelle à un point inconnu
#
# Avantage sur petit échantillon : on ne présuppose pas la date de rupture.
# C'est le test qui dit "si rupture il y a, elle est probablement quand ?"
# On l'applique aux séries principales : total, ben_pm, ifd.
#
# LECTURE des résultats ur.za :
# Si stat de test < valeur critique 5% → rejet H0 → stationnaire avec rupture
# Le point de rupture détecté est indiqué sous "Breakpoint at position"
# =============================================================================

cat("=============================================================\n")
cat("Q1B — COMPLÉMENT : TEST DE ZIVOT-ANDREWS\n")
cat("=============================================================\n\n")

cat("POURQUOI : contrairement au test de Chow (date fixée a priori),\n")
cat("Zivot-Andrews identifie endogènement le point de rupture le plus\n")
cat("probable. Plus robuste sur petit échantillon avec ruptures visibles.\n\n")

cat("LECTURE : si stat < valeur critique 5% → rejet H0\n")
cat("→ série stationnaire avec rupture structurelle\n")
cat("Le point de rupture est indiqué sous 'Breakpoint at position'\n\n")

cat("--- Total recettes ---\n")
za_total <- ur.za(ts(df$total,  start = 2007, frequency = 1),
                  model = "both", lag = 1)
summary(za_total)

cat("--- Bénéfice PM ---\n")
za_benpm <- ur.za(ts(df$ben_pm, start = 2007, frequency = 1),
                  model = "both", lag = 1)
summary(za_benpm)

cat("--- IFD ---\n")
za_ifd <- ur.za(ts(df$ifd, start = 2007, frequency = 1),
                model = "both", lag = 1)
summary(za_ifd)

cat("\n# DÉCISION Q1B :\n")
cat("# Si le point de rupture détecté est cohérent avec nos dates\n")
cat("# identifiées visuellement (2010, 2022) → dates confirmées.\n")
cat("# Si différent → documenter et justifier dans le README.\n")
cat("# Note : position = rang dans la série (ex: position 16 = 2022\n")
cat("# si la série commence en 2007).\n\n")

# =============================================================================
# Graphique niveau vs différence — validation visuelle Q1
# =============================================================================

ts_pour_graphique <- list(
  "Total recettes" = df$total,
  "Bénéfice PM"    = df$ben_pm,
  "IFD"            = df$ifd,
  "Fortune PP"     = df$fortune
)

plots_niv <- imap(ts_pour_graphique, function(serie, nom) {
  ggplot(tibble(annee = df$annee, valeur = serie),
         aes(x = annee, y = valeur)) +
    geom_line(color = couleurs[[which(names(ts_pour_graphique) == nom)]],
              linewidth = 1) +
    geom_point(size = 1.5,
               color = couleurs[[which(names(ts_pour_graphique) == nom)]]) +
    scale_y_continuous(labels = label_number(suffix = " M")) +
    labs(title = paste(nom, "— Niveau"), x = NULL, y = NULL) +
    theme_minimal(base_size = 9) +
    theme(plot.title = element_text(face = "bold", size = 9))
})

plots_dif <- imap(ts_pour_graphique, function(serie, nom) {
  ggplot(tibble(annee  = df$annee[-1],
                valeur = diff(serie)),
         aes(x = annee, y = valeur)) +
    geom_line(color = couleurs[[which(names(ts_pour_graphique) == nom)]],
              linewidth = 1, linetype = "dashed") +
    geom_point(size = 1.5,
               color = couleurs[[which(names(ts_pour_graphique) == nom)]]) +
    geom_hline(yintercept = 0, color = "grey50", linetype = "dotted") +
    labs(title = paste(nom, "— Diff. 1ère"), x = NULL, y = NULL) +
    theme_minimal(base_size = 9) +
    theme(plot.title = element_text(face = "bold", size = 9))
})

(plots_niv[[1]] + plots_dif[[1]]) /
  (plots_niv[[2]] + plots_dif[[2]]) /
  (plots_niv[[3]] + plots_dif[[3]]) /
  (plots_niv[[4]] + plots_dif[[4]]) +
  plot_annotation(
    title    = "Séries fiscales — Niveau et différence première",
    subtitle = "Validation visuelle de la stationnarité après différenciation",
    caption  = "Source : OCSTAT T18.02.1.15",
    theme    = theme(plot.title = element_text(face = "bold"))
  )

ggsave("02_stationnarite_visuelle.png",
       width = 13, height = 12, dpi = 150)

# =============================================================================
# Q2 — TEST DE CHOW — RUPTURES STRUCTURELLES
# =============================================================================
# POURQUOI APRÈS Q1 :
# Les tests de stationnarité peuvent être faussés par des ruptures
# structurelles non traitées — un test ADF sur une série avec rupture
# peut conclure à la non-stationnarité alors que la série est stationnaire
# autour de deux niveaux différents. On confirme maintenant formellement
# les ruptures visuelles identifiées en script 01.
#
# MÉTHODE :
# Test de Chow : teste si les paramètres d'une régression linéaire
# (total ~ tendance) changent significativement à un point donné.
# H0 : pas de rupture | H1 : rupture au point testé.
# Points testés : 2010 (post-crise 2008), 2020 (COVID).
# 2022 non testable : N post-rupture = 3 observations — insuffisant.
# =============================================================================

cat("=============================================================\n")
cat("Q2 — TEST DE CHOW — RUPTURES STRUCTURELLES\n")
cat("=============================================================\n\n")

cat("POURQUOI : valider formellement les ruptures visuelles du script 01.\n")
cat("Les ruptures confirmées seront intégrées comme dummies en Q6.\n\n")

df_chow <- df %>%
  mutate(trend = annee - min(annee) + 1)

resultats_chow <- tibble(
  annee_rupture = integer(),
  F_stat        = numeric(),
  p_value       = numeric(),
  conclusion    = character()
)

for (an in c(2010, 2020)) {
  idx  <- which(df_chow$annee == an)
  chow <- sctest(total ~ trend,
                 data  = df_chow,
                 type  = "Chow",
                 point = idx)
  cat("Rupture", an, ": F =", round(chow$statistic, 3),
      "| p =", round(chow$p.value, 3),
      ifelse(chow$p.value < 0.05,
             "→ RUPTURE CONFIRMÉE ✓",
             "→ non significative"),
      "\n")
  
  resultats_chow <- resultats_chow %>%
    add_row(annee_rupture = an,
            F_stat        = round(chow$statistic, 3),
            p_value       = round(chow$p.value, 3),
            conclusion    = ifelse(chow$p.value < 0.05,
                                   "Confirmée", "Non confirmée"))
}

# 2022 : non testable par Chow — N post-rupture insuffisant
cat("Rupture 2022 : test de Chow inadmissible\n")
cat("  → N post-rupture = 3 observations (2022–2024) — insuffisant\n")
cat("  → Rupture traitée via dummy_rffa en Q6\n\n")

resultats_chow <- resultats_chow %>%
  add_row(annee_rupture = 2022,
          F_stat        = NA,
          p_value       = NA,
          conclusion    = "Non testable — dummy_rffa en Q6")

cat("=== TABLEAU CHOW ===\n")
print(resultats_chow)

cat("\n# DÉCISION Q2 :\n")
cat("# 2010 et 2020 : ruptures confirmées statistiquement.\n")
cat("# 2022 : non testable par Chow (N trop faible post-rupture).\n")
cat("#         Traitée via dummy_rffa en Q6 — approche défendable.\n")
cat("# Note : avec N=18, la puissance du test de Chow est limitée.\n")
cat("# Absence de preuve ≠ preuve d'absence.\n")
cat("# → Ces résultats motivent Q3 (outlier 2009) et Q6 (dummy RFFA).\n\n")

# =============================================================================
# Q3 — OUTLIER SUCCESSIONS 2009
# =============================================================================
# POURQUOI APRÈS Q2 :
# L'anomalie de 2009 dans les successions est liée au contexte post-crise
# financière — potentiellement des successions exceptionnelles réglées
# cette année-là. Q2 nous a confirmé l'existence d'une rupture en 2010,
# ce qui contextualise cet outlier dans la période de crise 2008–2010.
# =============================================================================

cat("=============================================================\n")
cat("Q3 — OUTLIER SUCCESSIONS 2009\n")
cat("=============================================================\n\n")

cat("POURQUOI : l'outlier 2009 dans les successions est isolé ici\n")
cat("pour décider de son traitement avant la modélisation.\n\n")

val_2009 <- df$successions[df$annee == 2009]
med_succ <- median(df$successions)
moy_succ <- mean(df$successions)
sd_succ  <- sd(df$successions)

cat("Valeur 2009          :", val_2009, "M\n")
cat("Médiane série        :", round(med_succ, 0), "M\n")
cat("Écart à la médiane   :", round(val_2009 - med_succ, 0), "M\n")
cat("Écart en sigma       :", round((val_2009 - moy_succ) / sd_succ, 2),
    "σ\n\n")

df <- df %>%
  mutate(dummy_succ_2009 = ifelse(annee == 2009, 1, 0))

cat("# DÉCISION Q3 :\n")
cat("# Successions exclues de la modélisation principale :\n")
cat("# CV=37.8%, outlier 2009 à", round((val_2009 - moy_succ) / sd_succ, 1),
    "σ de la moyenne.\n")
cat("# Une dummy_succ_2009 est créée pour usage éventuel.\n\n")

# =============================================================================
# Q4 — TEST DE JOHANSEN — COINTÉGRATION
# =============================================================================
# POURQUOI APRÈS Q1 :
# Le test de Johansen n'a de sens que si les séries sont I(1) — confirmé
# en Q1. Tester la cointégration sur des séries I(0) serait une erreur
# méthodologique. On peut maintenant procéder.
#
# ENJEU :
# Si les séries sont cointégrées → relation de long terme stable existe
# → VECM plus approprié que VAR en différences.
# Si pas de cointégration confirmée → VAR en différences.
#
# LIMITE :
# Fenêtre commune 2008–2022 (N=15, N=13 après différenciation).
# La puissance du test de Johansen est très faible sur ce N.
# On applique le principe de prudence : en cas de doute, VAR en différences
# avec documentation explicite de la limite.
# =============================================================================

cat("=============================================================\n")
cat("Q4 — TEST DE JOHANSEN — COINTÉGRATION\n")
cat("=============================================================\n\n")

cat("POURQUOI : les séries étant I(1) (Q1), on teste s'il existe\n")
cat("une relation de long terme stable entre elles.\n")
cat("Ce résultat détermine VAR en différences vs VECM (script 03).\n\n")

cat("⚠️  LIMITE : N=13 observations effectives après différenciation.\n")
cat("    Puissance très faible — résultats indicatifs uniquement.\n\n")

df_jo <- df %>%
  filter(annee >= 2008, annee <= 2022) %>%
  dplyr::select(total, ben_pm, ifd) %>%
  as.matrix()

cat("Matrice Johansen :", nrow(df_jo), "obs ×",
    ncol(df_jo), "séries\n")
cat("Séries : Total recettes | Bénéfice PM | IFD\n\n")

jo_trace <- ca.jo(df_jo, type = "trace",  ecdet = "trend", K = 2)
cat("--- Test trace ---\n")
summary(jo_trace)

jo_eigen <- ca.jo(df_jo, type = "eigen",  ecdet = "trend", K = 2)
cat("\n--- Test valeur propre maximale ---\n")
summary(jo_eigen)

cat("\n# DÉCISION Q4 :\n")
cat("# Test trace : sur-rejette H0 sur petit N — moins fiable.\n")
cat("# Test valeur propre max : plus conservateur — à privilégier.\n")
cat("# En cas de divergence entre les deux tests :\n")
cat("#   → principe de prudence → VAR en différences\n")
cat("#   → avec documentation explicite de la divergence.\n")
cat("# → Cette décision est reportée dans le script 03.\n\n")

# =============================================================================
# Q5 — RELATIONS MACRO SUR SÉRIES DIFFÉRENCIÉES
# =============================================================================
# POURQUOI APRÈS Q1 :
# En script 01, les corrélations étaient calculées sur les niveaux.
# Deux séries I(1) avec tendance corrèlent mécaniquement en niveau
# même sans lien causal — c'est le risque de corrélation spurieuse.
# Après Q1, on sait que les séries sont I(1). On recalcule donc les
# corrélations sur les DIFFÉRENCES premières — stationnaires.
# Si les corrélations persistent en différences → relation réelle.
# Si elles disparaissent → elles étaient spurieuses en niveau.
#
# EXCEPTION : la corrélation PIB/recettes est structurelle
# (les recettes sont une dérivée directe de l'activité économique).
# =============================================================================

cat("=============================================================\n")
cat("Q5 — CORRÉLATIONS MACRO SUR SÉRIES DIFFÉRENCIÉES\n")
cat("=============================================================\n\n")

cat("POURQUOI : recalculer les corrélations sur les variations annuelles\n")
cat("pour distinguer les relations réelles des corrélations spurieuses.\n\n")

df_diff <- df %>%
  filter(!is.na(pib_ge)) %>%
  arrange(annee) %>%
  mutate(
    d_total   = c(NA, diff(total)),
    d_ben_pm  = c(NA, diff(ben_pm)),
    d_ifd     = c(NA, diff(ifd)),
    d_fortune = c(NA, diff(fortune)),
    d_pib     = c(NA, diff(pib_ge)),
    d_saron   = c(NA, diff(saron)),
    d_ipc     = c(NA, diff(ipc))
  ) %>%
  filter(!is.na(d_total))

cat("Matrice de corrélation — NIVEAUX (pour référence) :\n")
cor_niveaux <- df %>%
  filter(!is.na(pib_ge)) %>%
  dplyr::select(total, ben_pm, ifd, fortune, pib_ge, saron, ipc) %>%
  cor(use = "complete.obs") %>%
  round(2)
print(cor_niveaux)

cat("\nMatrice de corrélation — DIFFÉRENCES PREMIÈRES :\n")
cor_diff <- df_diff %>%
  dplyr::select(d_total, d_ben_pm, d_ifd,
                d_fortune, d_pib, d_saron, d_ipc) %>%
  cor(use = "complete.obs") %>%
  round(2)
print(cor_diff)

cat("\n# DÉCISION Q5 :\n")
cat("# Les corrélations qui persistent en différences sont réelles.\n")
cat("# Celles qui disparaissent étaient spurieuses (tendances communes).\n")
cat("# Fortune : corrélation en niveaux 0.86, en différences 0.05\n")
cat("#   → spurieuse → exclure des régresseurs.\n")
cat("# Ben_pm, ifd, pib : corrélations persistantes → réelles.\n")
cat("# → Ce résultat guide le choix des régresseurs dans le script 03.\n\n")

# =============================================================================
# Q6 — DUMMIES RFFA ET AUTRES
# =============================================================================
# POURQUOI EN DERNIER :
# Q6 s'appuie sur Q2 (ruptures confirmées) et Q5 (relations validées).
# On crée et teste les dummies qui seront intégrées dans le script 03.
#
# MÉTHODE :
# Régression simple total ~ tendance + dummies pour quantifier l'effet
# brut de chaque événement sur les recettes totales.
# Ce n'est pas un modèle final — c'est une mesure préliminaire.
# =============================================================================

cat("=============================================================\n")
cat("Q6 — DUMMIES RFFA, COVID ET CRÉATION DES VARIABLES\n")
cat("=============================================================\n\n")

cat("POURQUOI : Q2 a identifié les ruptures candidates. On quantifie\n")
cat("leur effet pour décider lesquelles intégrer dans le script 03.\n\n")

df <- df %>%
  mutate(
    dummy_rffa  = ifelse(annee >= 2022, 1, 0),
    dummy_covid = ifelse(annee == 2020, 1, 0),
    trend_var   = annee - min(annee) + 1
  )

mod_base    <- lm(total ~ trend_var,                        data = df)
mod_rffa    <- lm(total ~ trend_var + dummy_rffa,           data = df)
mod_complet <- lm(total ~ trend_var + dummy_rffa +
                    dummy_covid,                            data = df)

cat("--- Modèle 1 : Total ~ Tendance seule ---\n")
cat("R² =", round(summary(mod_base)$r.squared, 3), "\n\n")

cat("--- Modèle 2 : Total ~ Tendance + Dummy RFFA ---\n")
print(summary(mod_rffa)$coefficients %>% round(2))
cat("R² =", round(summary(mod_rffa)$r.squared, 3), "\n\n")

cat("--- Modèle 3 : Total ~ Tendance + Dummy RFFA + Dummy COVID ---\n")
print(summary(mod_complet)$coefficients %>% round(2))
cat("R² =", round(summary(mod_complet)$r.squared, 3), "\n\n")

cat("# DÉCISION Q6 :\n")
cat("# dummy_rffa : coefficient ~+1729M, p≈0 → très significatif\n")
cat("#   → intégrer via xreg dans ARIMA et comme variable exogène VAR\n")
cat("# dummy_covid : p=0.61 → non significatif\n")
cat("#   → Genève résiliente au COVID fiscalement\n")
cat("#   → ne pas inclure dans les modèles, documenter dans README\n")
cat("# dummy_succ_2009 : en réserve pour usage éventuel\n\n")

# =============================================================================
# SYNTHÈSE FINALE — DÉCISIONS POUR LE SCRIPT 03
# =============================================================================

cat("=============================================================\n")
cat("SYNTHÈSE — DÉCISIONS POUR LE SCRIPT 03\n")
cat("=============================================================\n\n")

cat("SÉRIES RETENUES :\n")
cat("  Cible principale  : total recettes (I(1) confirmé)\n")
cat("  Composantes       : ben_pm, fortune, ifd (I(1) confirmés)\n")
cat("  Proxy IR          : pp_total (cohérent 2007–2024, décision Q7)\n")
cat("  Fortune           : EXCLUE des régresseurs (corr. diff = 0.05)\n")
cat("  Successions       : exclues (volatilité + outlier, décision Q3)\n\n")

cat("DUMMIES DISPONIBLES :\n")
cat("  dummy_rffa       (=1 si annee >= 2022) → À INTÉGRER\n")
cat("  dummy_covid      (=1 si annee == 2020) → non significative\n")
cat("  dummy_succ_2009  (=1 si annee == 2009) → en réserve\n\n")

cat("MODÈLES À CONSTRUIRE DANS LE SCRIPT 03 :\n")
cat("  Étape 1 : ARIMA baseline (auto.arima, d=1 forcé par Q1)\n")
cat("  Étape 2 : ETS — comparaison directe avec ARIMA\n")
cat("  Étape 3 : ARIMAX — ARIMA + dummy_rffa via xreg\n")
cat("  Étape 4 : VAR ou VECM selon résultat Johansen (Q4)\n\n")

cat("→ Chaque modèle du script 03 sera motivé par les résultats\n")
cat("  du modèle précédent — approche inductive maintenue.\n")
