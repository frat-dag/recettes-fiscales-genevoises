# =============================================================================
# PROJET : ANALYSE & PRÉVISION DES RECETTES FISCALES GENEVOISES
# Script  : 03_modeles.R
# Auteur  : Frat DAG
# Date    : Avril 2026
# Version : 2.0 — approche inductive
# =============================================================================
# CE QU'ON SAIT APRÈS LE SCRIPT 02 :
#
# STATIONNARITÉ (Q1 + KPSS + Zivot-Andrews) :
#   - Total recettes : I(1) confirmé trois tests + rupture ZA ~2018
#   - PP total       : I(1) confirmé trois tests
#   - Bénéfice PM    : I(1) probable + rupture ZA ~2019
#   - Fortune PP     : I(1) confirmé — mais corrélation diff spurieuse
#   - IFD            : I(1) via KPSS
#   - Enreg. timbre  : ambigu — régresseur potentiel uniquement
#     (= "Produits de l'enregistrement et timbre" nomenclature OCSTAT)
#
# RUPTURES (Q2 Chow) :
#   - 2010 : confirmée (F=4.197, p=0.037)
#   - 2020 : confirmée (F=18.59, p≈0)
#   - 2022 : non testable Chow — traitée via dummy_rffa
#
# COINTÉGRATION (Q4 Johansen) :
#   - Test trace : sur-rejette H0 (peu fiable sur N=13)
#   - Test valeur propre max : non rejet de H0 à 5%
#   - Principe de prudence → VAR en différences
#
# DUMMIES :
#   - dummy_rffa  : +1729M, p≈0 → À INTÉGRER
#   - dummy_covid : p=0.61 → exclue, documenter résilience genevoise
#
# CORRECTION NOMENCLATURE :
#   - "droits_mut" renommé "enreg_timbre" partout dans ce script
#   - Label : "Enregistrement et timbre (OCSTAT)"
#
# MODÈLES À CONSTRUIRE (dans l'ordre de complexité croissante) :
#   Étape 1 : ARIMA baseline
#   Étape 2 : ETS — comparaison avec ARIMA
#   Étape 3 : ARIMAX — ARIMA + dummy_rffa
#   Étape 4 : VAR en différences
# =============================================================================

library(tidyverse)
library(forecast)    # auto.arima, ets, forecast
library(vars)        # VAR, VARselect
library(ggplot2)
library(patchwork)
library(scales)

# -----------------------------------------------------------------------------
# 0. VÉRIFICATION + CORRECTION NOMENCLATURE
# -----------------------------------------------------------------------------

if (!exists("df")) {
  stop("L'objet 'df' n'est pas en mémoire. Relancer scripts 01 et 02.")
}
cat("✓ Objet 'df' disponible :", nrow(df), "observations\n")
cat("✓ Dummies disponibles :",
    paste(names(df)[grepl("dummy", names(df))], collapse = ", "), "\n\n")

# Vérification nomenclature enreg_timbre
# Le renommage droits_mut → enreg_timbre est effectué dans le script 01.
# On vérifie ici que la colonne est bien présente.
if (!"enreg_timbre" %in% names(df)) {
  df <- df %>% rename(enreg_timbre = droits_mut)
}
cat("✓ Nomenclature enreg_timbre confirmée\n\n")

couleurs <- c("#2C3E50", "#E74C3C", "#2980B9", "#27AE60", "#F39C12")

# Objets ts pour la modélisation
ts_total <- ts(df$total, start = 2007, frequency = 1)

# =============================================================================
# ÉTAPE 1 — ARIMA BASELINE
# =============================================================================
# POURQUOI EN PREMIER :
# L'ARIMA est le modèle de référence (baseline) — le plus simple qui
# capture la dynamique temporelle. On commence par lui pour établir
# un niveau de performance minimal que les modèles suivants devront
# dépasser pour justifier leur complexité supplémentaire.
#
# PARAMÈTRES :
# d=1 forcé par les conclusions du script 02 (Q1 — séries I(1))
# stepwise=FALSE et approximation=FALSE : exploration exhaustive
# Sur N=18, c'est faisable sans coût computationnel excessif
#
# POURQUOI ARIMA ET PAS SARIMA ?
# Données annuelles — pas de saisonnalité. SARIMA inutile et
# injustifié sur cette fréquence.
# =============================================================================

cat("=============================================================\n")
cat("ÉTAPE 1 — ARIMA BASELINE\n")
cat("=============================================================\n\n")

cat("POURQUOI : établir le modèle de référence le plus simple.\n")
cat("d=1 forcé par Q1 (script 02). Exploration exhaustive (stepwise=FALSE).\n\n")

arima_base <- auto.arima(
  ts_total,
  d             = 1,
  stepwise      = FALSE,
  approximation = FALSE,
  trace         = TRUE
)

cat("\n--- Modèle ARIMA retenu ---\n")
summary(arima_base)

# Diagnostics des résidus
cat("\n--- Diagnostics résidus ARIMA baseline ---\n")
lb_base <- Box.test(residuals(arima_base), lag = 5, type = "Ljung-Box")
cat("Ljung-Box p =", round(lb_base$p.value, 3),
    ifelse(lb_base$p.value > 0.05,
           "→ résidus non autocorrélés ✓",
           "→ autocorrélation résiduelle — modèle à revoir"),
    "\n")

# RMSE en training
rmse_arima_base <- accuracy(arima_base)["Training set", "RMSE"]
cat("RMSE training :", round(rmse_arima_base, 0), "M CHF\n")

# Prévisions ARIMA baseline — horizon 3 ans
prev_arima_base <- forecast(arima_base, h = 3)
cat("\nPrévisions ARIMA baseline 2025–2027 :\n")
print(prev_arima_base)

cat("\n# DÉCISION ÉTAPE 1 :\n")
cat("# Modèle retenu :", arima_base$arma, "\n")
cat("# RMSE =", round(rmse_arima_base, 0), "M CHF — référence à battre\n")
cat("# Ljung-Box p =", round(lb_base$p.value, 3), "\n")
cat("# → Ce RMSE et ces prévisions sont la baseline.\n")
cat("# → L'Étape 2 (ETS) doit produire un RMSE inférieur pour justifier\n")
cat("#   sa complexité supplémentaire.\n\n")

# =============================================================================
# ÉTAPE 2 — MODÈLE ETS
# =============================================================================
# POURQUOI APRÈS ARIMA :
# L'ARIMA est notre baseline. L'ETS (Error, Trend, Seasonality) est une
# alternative directe pour les séries temporelles courtes.
# Avantage ETS vs ARIMA : ne nécessite pas d'hypothèse de stationnarité
# préalable — il modélise directement le niveau et la tendance.
# Sur petit N, ETS est souvent plus stable qu'ARIMA.
#
# Si ETS > ARIMA (RMSE inférieur) → ETS devient la nouvelle baseline.
# Si ETS ≈ ARIMA → les deux modèles convergent, résultat robuste.
# Si ETS < ARIMA → ARIMA reste préféré (parcimonie).
# =============================================================================

cat("=============================================================\n")
cat("ÉTAPE 2 — MODÈLE ETS\n")
cat("=============================================================\n\n")

cat("POURQUOI : alternative à ARIMA ne nécessitant pas de stationnarité.\n")
cat("Sur petit N, ETS souvent plus stable. Comparaison directe avec ARIMA.\n\n")

ets_model <- ets(ts_total)

cat("--- Modèle ETS retenu ---\n")
summary(ets_model)

# Diagnostics
lb_ets <- Box.test(residuals(ets_model), lag = 5, type = "Ljung-Box")
cat("\nLjung-Box p =", round(lb_ets$p.value, 3),
    ifelse(lb_ets$p.value > 0.05,
           "→ résidus non autocorrélés ✓",
           "→ autocorrélation résiduelle"),
    "\n")

rmse_ets <- accuracy(ets_model)["Training set", "RMSE"]
cat("RMSE training :", round(rmse_ets, 0), "M CHF\n")

# Prévisions ETS
prev_ets <- forecast(ets_model, h = 3)
cat("\nPrévisions ETS 2025–2027 :\n")
print(prev_ets)

# Comparaison ARIMA vs ETS
cat("\n--- Comparaison ARIMA baseline vs ETS ---\n")
comp_1_2 <- tibble(
  Modele      = c("ARIMA baseline", "ETS"),
  RMSE        = round(c(rmse_arima_base, rmse_ets), 0),
  LjungBox_p  = round(c(lb_base$p.value, lb_ets$p.value), 3),
  Prev_2025   = round(c(as.numeric(prev_arima_base$mean[1]),
                        as.numeric(prev_ets$mean[1])), 0),
  Prev_2026   = round(c(as.numeric(prev_arima_base$mean[2]),
                        as.numeric(prev_ets$mean[2])), 0),
  Prev_2027   = round(c(as.numeric(prev_arima_base$mean[3]),
                        as.numeric(prev_ets$mean[3])), 0)
)
print(comp_1_2)

cat("\n# DÉCISION ÉTAPE 2 :\n")
if (rmse_ets < rmse_arima_base) {
  cat("# ETS RMSE inférieur → ETS devient la nouvelle référence.\n")
  cat("# L'Étape 3 (ARIMAX) sera comparée à ETS.\n\n")
  modele_ref     <- ets_model
  prev_ref       <- prev_ets
  rmse_ref       <- rmse_ets
  nom_ref        <- "ETS"
} else {
  cat("# ARIMA RMSE inférieur ou égal → ARIMA reste la référence.\n")
  cat("# L'Étape 3 (ARIMAX) doit battre ARIMA pour être retenu.\n\n")
  modele_ref     <- arima_base
  prev_ref       <- prev_arima_base
  rmse_ref       <- rmse_arima_base
  nom_ref        <- "ARIMA baseline"
}

# =============================================================================
# ÉTAPE 3 — ARIMAX (ARIMA + RÉGRESSEURS EXTERNES)
# =============================================================================
# POURQUOI APRÈS ARIMA ET ETS :
# On sait maintenant que le modèle univarié de référence est [nom_ref].
# On teste si l'ajout de la dummy_rffa (identifiée en Q6 script 02)
# améliore les performances.
#
# POURQUOI dummy_rffa ET PAS d'autres variables ?
# Q5 (script 02) a montré que les corrélations en différences persistantes
# sont : ben_pm (0.71), pib (0.61), ifd (0.50).
# Mais ben_pm, pib et ifd sont eux-mêmes des composantes ou dérivées des
# recettes fiscales — les inclure comme régresseurs crée un risque de
# multicolinéarité et de circularité.
# La dummy_rffa est exogène par construction — c'est la variable externe
# la plus propre disponible.
#
# MÉTHODE : auto.arima avec xreg = matrice des régresseurs
# On force d=1 pour cohérence avec l'Étape 1.
# =============================================================================

cat("=============================================================\n")
cat("ÉTAPE 3 — ARIMAX (ARIMA + dummy_rffa)\n")
cat("=============================================================\n\n")

cat("POURQUOI : tester si l'ajout de dummy_rffa améliore le modèle\n")
cat("de référence. dummy_rffa est exogène — pas de risque de circularité.\n")
cat("Référence actuelle :", nom_ref, "| RMSE =",
    round(rmse_ref, 0), "M CHF\n\n")

# Matrice de régresseurs pour l'estimation
xreg_train <- matrix(df$dummy_rffa, ncol = 1,
                     dimnames = list(NULL, "dummy_rffa"))

arima_x <- auto.arima(
  ts_total,
  d             = 1,
  xreg          = xreg_train,
  stepwise      = FALSE,
  approximation = FALSE,
  trace         = TRUE
)

cat("\n--- Modèle ARIMAX retenu ---\n")
summary(arima_x)

# Diagnostics
lb_x <- Box.test(residuals(arima_x), lag = 5, type = "Ljung-Box")
cat("\nLjung-Box p =", round(lb_x$p.value, 3),
    ifelse(lb_x$p.value > 0.05,
           "→ résidus non autocorrélés ✓",
           "→ autocorrélation résiduelle"),
    "\n")

rmse_arimax <- accuracy(arima_x)["Training set", "RMSE"]
cat("RMSE training :", round(rmse_arimax, 0), "M CHF\n")
cat("RMSE référence:", round(rmse_ref, 0), "M CHF\n")
cat("Amélioration  :", round(rmse_ref - rmse_arimax, 0),
    "M CHF (", round((rmse_ref - rmse_arimax) / rmse_ref * 100, 1),
    "%)\n")

# Prévisions ARIMAX — horizon 3 ans
# Pour les années futures, dummy_rffa = 1 (on suppose que l'effet RFFA persiste)
xreg_prev <- matrix(rep(1, 3), ncol = 1,
                    dimnames = list(NULL, "dummy_rffa"))

prev_arimax <- forecast(arima_x, h = 3, xreg = xreg_prev)
cat("\nPrévisions ARIMAX 2025–2027 :\n")
print(prev_arimax)

cat("\n# DÉCISION ÉTAPE 3 :\n")
if (rmse_arimax < rmse_ref) {
  cat("# ARIMAX améliore le modèle de référence.\n")
  cat("# dummy_rffa apporte une information réelle.\n")
  cat("# → ARIMAX devient le modèle économétrique retenu.\n\n")
  modele_final_eco <- "ARIMAX"
  prev_final_eco   <- prev_arimax
  rmse_final_eco   <- rmse_arimax
} else {
  cat("# ARIMAX n'améliore pas suffisamment le modèle de référence.\n")
  cat("# L'ajout de dummy_rffa ne justifie pas la complexité.\n")
  cat("# →", nom_ref, "reste le modèle économétrique retenu.\n\n")
  modele_final_eco <- nom_ref
  prev_final_eco   <- prev_ref
  rmse_final_eco   <- rmse_ref
}

# =============================================================================
# ÉTAPE 4 — VAR EN DIFFÉRENCES
# =============================================================================
# POURQUOI APRÈS LES MODÈLES UNIVARIÉS :
# Les modèles ARIMA et ETS sont univariés — ils n'utilisent que l'historique
# du total des recettes. Le VAR capture les interactions entre plusieurs
# séries simultanément.
#
# POURQUOI VAR EN DIFFÉRENCES ET PAS VECM ?
# Le test de Johansen (Q4, script 02) montre une divergence entre test
# trace et test valeur propre max. Par principe de prudence, on choisit
# VAR en différences — plus conservateur sur petit échantillon.
# Cette décision est documentée et défendable.
#
# VARIABLES RETENUES POUR LE VAR :
# - d_total   : différence première du total (variable cible)
# - d_ben_pm  : différence première du bénéfice PM (corr. diff = 0.71)
# - d_saron   : différence première du SARON (corr. diff = 0.44)
# On exclut : fortune (corr. diff spurieuse = 0.05), pib (trop de NA)
#
# FENÊTRE : 2008–2022 (contrainte PIB) — N=14 après différenciation
# =============================================================================

cat("=============================================================\n")
cat("ÉTAPE 4 — VAR EN DIFFÉRENCES\n")
cat("=============================================================\n\n")

cat("POURQUOI : capturer les interactions entre séries fiscales et macro.\n")
cat("VAR en différences (pas VECM) — décision Q4 script 02.\n")
cat("Variables : d_total, d_ben_pm, d_saron\n\n")

# Préparation données VAR
df_var <- df %>%
  filter(annee >= 2008, annee <= 2022) %>%
  arrange(annee) %>%
  mutate(
    d_total  = c(NA, diff(total)),
    d_ben_pm = c(NA, diff(ben_pm)),
    d_saron  = c(NA, diff(saron))
  ) %>%
  filter(!is.na(d_total)) %>%
  dplyr::select(annee, d_total, d_ben_pm, d_saron)

cat("Dimensions VAR :", nrow(df_var), "obs ×",
    ncol(df_var) - 1, "variables\n")
cat("Période :", min(df_var$annee), "–", max(df_var$annee), "\n\n")

ts_var <- ts(df_var %>% dplyr::select(-annee),
             start = 2009, frequency = 1)

# Sélection du nombre de lags
cat("--- Sélection du nombre de lags ---\n")
cat("⚠️  Avec N=14 et 3 variables, p=1 est la seule option raisonnable.\n")
cat("    p=2 consommerait trop de degrés de liberté.\n\n")

var_select <- VARselect(ts_var, lag.max = 2, type = "const")
cat("Critères de sélection :\n")
print(var_select$selection)

# Ajustement VAR(1)
cat("\n--- Ajustement VAR(1) ---\n")
var_model <- VAR(ts_var, p = 1, type = "const")
summary(var_model)

# Diagnostic
cat("\n--- Test de Portmanteau sur les résidus VAR ---\n")
port_test <- serial.test(var_model, lags.pt = 5,
                         type = "PT.asymptotic")
print(port_test)

# Prévisions VAR
cat("\n--- Prévisions VAR 2025–2027 (différences) ---\n")
prev_var_diff <- predict(var_model, n.ahead = 3)

# Reconstitution des niveaux
derniere_val <- df$total[df$annee == 2022]
diff_prevues <- prev_var_diff$fcst$d_total[, "fcst"]
niveaux_var  <- cumsum(c(derniere_val, diff_prevues))[-1]

cat("Prévisions VAR — niveaux reconstitués (M CHF) :\n")
cat("2025 :", round(niveaux_var[1]), "M\n")
cat("2026 :", round(niveaux_var[2]), "M\n")
cat("2027 :", round(niveaux_var[3]), "M\n")

cat("\n# DÉCISION ÉTAPE 4 :\n")
cat("# VAR(1) sur N=14 — surparamétrage inévitable.\n")
cat("# Aucun coefficient n'est attendu comme fortement significatif.\n")
cat("# Le VAR est présenté comme modèle exploratoire complémentaire,\n")
cat("# pas comme modèle de référence.\n")
cat("# → Le modèle économétrique retenu reste :", modele_final_eco, "\n\n")

# =============================================================================
# SYNTHÈSE — COMPARAISON DES MODÈLES
# =============================================================================

cat("=============================================================\n")
cat("SYNTHÈSE — COMPARAISON DES QUATRE MODÈLES\n")
cat("=============================================================\n\n")

comparaison <- tibble(
  Modele     = c("ARIMA baseline", "ETS",
                 "ARIMAX (+dummy_rffa)", "VAR(1)"),
  RMSE_train = c(round(rmse_arima_base, 0),
                 round(rmse_ets, 0),
                 round(rmse_arimax, 0),
                 NA),
  LjungBox_p = c(round(lb_base$p.value, 3),
                 round(lb_ets$p.value, 3),
                 round(lb_x$p.value, 3),
                 NA),
  Prev_2025  = c(round(as.numeric(prev_arima_base$mean[1]), 0),
                 round(as.numeric(prev_ets$mean[1]), 0),
                 round(as.numeric(prev_arimax$mean[1]), 0),
                 round(niveaux_var[1], 0)),
  Prev_2026  = c(round(as.numeric(prev_arima_base$mean[2]), 0),
                 round(as.numeric(prev_ets$mean[2]), 0),
                 round(as.numeric(prev_arimax$mean[2]), 0),
                 round(niveaux_var[2], 0)),
  Statut     = c(ifelse(modele_final_eco == "ARIMA baseline",
                        "RETENU ✓", "Référence initiale"),
                 ifelse(modele_final_eco == "ETS",
                        "RETENU ✓", "Comparaison"),
                 ifelse(modele_final_eco == "ARIMAX",
                        "RETENU ✓", "Comparaison"),
                 "Exploratoire")
)

print(comparaison)

# =============================================================================
# GRAPHIQUES DE PRÉVISION
# =============================================================================

# Données historiques + prévisions pour graphique
df_hist <- tibble(
  annee  = df$annee,
  valeur = df$total,
  type   = "Historique"
)

df_prev_graph <- bind_rows(
  tibble(annee  = 2025:2027,
         valeur = as.numeric(prev_arima_base$mean),
         type   = "ARIMA baseline"),
  tibble(annee  = 2025:2027,
         valeur = as.numeric(prev_ets$mean),
         type   = "ETS"),
  tibble(annee  = 2025:2027,
         valeur = as.numeric(prev_arimax$mean),
         type   = "ARIMAX"),
  tibble(annee  = 2025:2027,
         valeur = niveaux_var,
         type   = "VAR(1)")
)

df_graph <- bind_rows(df_hist, df_prev_graph)

# Intervalles de confiance ARIMAX (modèle retenu)
df_ic <- tibble(
  annee = 2025:2027,
  lo95  = as.numeric(prev_arimax$lower[, 2]),
  hi95  = as.numeric(prev_arimax$upper[, 2]),
  lo80  = as.numeric(prev_arimax$lower[, 1]),
  hi80  = as.numeric(prev_arimax$upper[, 1])
)

g_prev <- ggplot() +
  # Intervalles de confiance ARIMAX
  geom_ribbon(data = df_ic,
              aes(x = annee, ymin = lo95, ymax = hi95),
              fill = couleurs[3], alpha = 0.12) +
  geom_ribbon(data = df_ic,
              aes(x = annee, ymin = lo80, ymax = hi80),
              fill = couleurs[3], alpha = 0.22) +
  # Série historique
  geom_line(data = filter(df_graph, type == "Historique"),
            aes(x = annee, y = valeur),
            color = couleurs[1], linewidth = 1.3) +
  geom_point(data = filter(df_graph, type == "Historique"),
             aes(x = annee, y = valeur),
             color = couleurs[1], size = 2) +
  # Prévisions
  geom_line(data = filter(df_graph, type != "Historique"),
            aes(x = annee, y = valeur, color = type),
            linewidth = 1.0, linetype = "dashed") +
  geom_point(data = filter(df_graph, type != "Historique"),
             aes(x = annee, y = valeur, color = type),
             size = 2.5, shape = 17) +
  scale_color_manual(values = c(
    "ARIMA baseline" = couleurs[2],
    "ETS"            = couleurs[4],
    "ARIMAX"         = couleurs[3],
    "VAR(1)"         = couleurs[5]
  )) +
  scale_y_continuous(
    labels = label_number(scale = 1/1000, suffix = " Mrd CHF")
  ) +
  scale_x_continuous(breaks = seq(2007, 2027, by = 2)) +
  geom_vline(xintercept = 2024.5, linetype = "dotted",
             color = "grey50") +
  annotate("text", x = 2024.7, y = 6200,
           label = "Horizon\nprévision", size = 3,
           color = "grey50", hjust = 0) +
  labs(
    title    = "Comparaison des modèles de prévision — Total recettes GE",
    subtitle = paste0("ARIMA, ETS, ARIMAX et VAR(1) | 2025–2027\n",
                      "Zone grisée : intervalles de confiance ARIMAX ",
                      "(80% et 95%)"),
    x = NULL, y = NULL,
    color    = NULL,
    caption  = paste0("Source : OCSTAT T18.02.1.15 | ",
                      "Modèle retenu : ", modele_final_eco)
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "bottom"
  )

print(g_prev)
ggsave("03_comparaison_modeles.png",
       g_prev, width = 13, height = 7, dpi = 150)

# Graphique diagnostic résidus — modèle retenu
par(mfrow = c(2, 2))
if (modele_final_eco == "ARIMAX") {
  plot(residuals(arima_x),
       main = paste("Résidus —", modele_final_eco),
       col = couleurs[3])
  abline(h = 0, lty = 2, col = "grey50")
  acf(residuals(arima_x),  main = "ACF des résidus")
  pacf(residuals(arima_x), main = "PACF des résidus")
  qqnorm(residuals(arima_x), main = "Q-Q plot")
  qqline(residuals(arima_x), col = couleurs[2])
} else {
  plot(residuals(arima_base),
       main = paste("Résidus —", modele_final_eco),
       col = couleurs[1])
  abline(h = 0, lty = 2, col = "grey50")
  acf(residuals(arima_base),  main = "ACF des résidus")
  pacf(residuals(arima_base), main = "PACF des résidus")
  qqnorm(residuals(arima_base), main = "Q-Q plot")
  qqline(residuals(arima_base), col = couleurs[2])
}
par(mfrow = c(1, 1))

ggsave("03_residus_modele_retenu.png",
       width = 10, height = 8, dpi = 150)

cat("\n✓ Étape 3 terminée.\n")
cat("Modèle économétrique retenu :", modele_final_eco, "\n")
cat("RMSE :", round(rmse_final_eco, 0), "M CHF\n")
cat("Graphiques sauvegardés.\n")
cat("→ Prochaine étape : analyse SHAP des drivers (script 04)\n")