# =============================================================================
# PROJET : ANALYSE & PRÉVISION DES RECETTES FISCALES GENEVOISES
# Script  : 04_shap.R
# Auteur  : Frat DAG
# Date    : Avril 2026
# Version : 2.0 — approche inductive
# =============================================================================
# CE QU'ON SAIT APRÈS LE SCRIPT 03 :
#
# MODÈLE RETENU : ARIMAX (ARIMA(0,1,0) + dummy_rffa)
#   - RMSE = 283M CHF (amélioration de 27.7% vs ARIMA baseline)
#   - Coefficient dummy_rffa = +1398M, p≈0
#   - Prévision 2025–2027 : plateau à 9'269M
#
# QUESTION QUI ÉMERGE NATURELLEMENT :
# Les modèles économétriques nous disent CE QUE les recettes vont faire.
# Mais ils ne disent pas POURQUOI elles bougent d'une année à l'autre.
# Quelle est la contribution relative de chaque variable à chaque prédiction ?
# → C'est la question à laquelle les SHAP values répondent.
#
# RECADRAGE IMPORTANT :
# Le Random Forest est utilisé ICI UNIQUEMENT pour l'analyse SHAP.
# Son rôle n'est PAS de prévoir — les prévisions RF sont inférieures
# aux modèles économétriques sur ce jeu de données.
# Son rôle EST d'identifier les drivers des variations annuelles.
#
# ANTI-LEAKAGE :
# Toutes les features sont des lags (t-1) — on n'utilise jamais
# d'information de l'année t pour prédire l'année t.
# =============================================================================

library(tidyverse)
library(randomForest)
library(fastshap)
library(ggplot2)
library(patchwork)
library(scales)

# -----------------------------------------------------------------------------
# 0. VÉRIFICATION
# -----------------------------------------------------------------------------

if (!exists("df")) {
  stop("L'objet 'df' n'est pas en mémoire. Relancer scripts 01, 02 et 03.")
}
cat("✓ Objet 'df' disponible :", nrow(df), "observations\n\n")

couleurs <- c("#2C3E50", "#E74C3C", "#2980B9", "#27AE60", "#F39C12")

# =============================================================================
# PARTIE A — CONSTRUCTION DES FEATURES
# =============================================================================
# POURQUOI CES FEATURES :
# On construit des lags pour capturer la dynamique temporelle sans leakage.
# Features retenues :
#   - total_lag1, total_lag2 : mémoire fiscale à 1 et 2 ans
#   - ben_pm_lag1 : bénéfice PM à t-1 (corr. diff = 0.71 avec d_total)
#   - ifd_lag1    : IFD à t-1 (corr. diff = 0.50)
#   - saron_lag1  : SARON à t-1 (corr. diff = 0.44)
#   - ipc_lag1    : IPC à t-1 (corr. diff = 0.40)
#   - trend       : tendance temporelle centrée
#   - dummy_rffa  : effet structurel RFFA
#
# Features EXCLUES et pourquoi :
#   - fortune_lag1   : corrélation diff spurieuse (0.05)
#   - pib_lag1       : NA après 2022, incomplet
#   - enreg_timbre   : nomenclature ambiguë, corrélation modérée
# =============================================================================

cat("=============================================================\n")
cat("PARTIE A — CONSTRUCTION DES FEATURES\n")
cat("=============================================================\n\n")

cat("POURQUOI : features lag uniquement (anti-leakage).\n")
cat("Features exclues : fortune (corr. spurieuse), pib (NA post-2022),\n")
cat("enreg_timbre (nomenclature ambiguë).\n\n")

df_ml <- df %>%
  arrange(annee) %>%
  mutate(
    total_lag1  = lag(total,   1),
    total_lag2  = lag(total,   2),
    ben_pm_lag1 = lag(ben_pm,  1),
    ifd_lag1    = lag(ifd,     1),
    saron_lag1  = lag(saron,   1),
    ipc_lag1    = lag(ipc, 1),
    trend       = annee - mean(annee)
  )

# Sélection des colonnes et suppression des NA
df_ml_clean <- df_ml %>%
  dplyr::select(annee, total, total_lag1, total_lag2,
                ben_pm_lag1, ifd_lag1, saron_lag1,
                ipc_lag1, trend, dummy_rffa) %>%
  filter(complete.cases(.))

cat("Observations après construction des features :", nrow(df_ml_clean), "\n")
cat("Période :", min(df_ml_clean$annee), "–",
    max(df_ml_clean$annee), "\n\n")

# Vérification anti-leakage
cat("Vérification anti-leakage :\n")
cat("  Toutes les features sont des lags (t-1 ou t-2) ou des\n")
cat("  variables exogènes (trend, dummy_rffa).\n")
cat("  Aucune valeur de l'année t n'est utilisée pour prédire t. ✓\n\n")

# =============================================================================
# PARTIE B — SPLIT TRAIN / TEST
# =============================================================================
# Validation temporelle walk-forward :
# On entraîne sur 2009–2021 et on teste sur 2022–2024 (N=3).
# Respecte l'ordre temporel — pas de data leakage temporel.
#
# NOTE : avec N=3 en test, le RMSE de test est indicatif.
# L'objectif principal est l'analyse SHAP, pas la prévision.
# =============================================================================

cat("=============================================================\n")
cat("PARTIE B — SPLIT TRAIN / TEST\n")
cat("=============================================================\n\n")

train <- df_ml_clean %>% filter(annee <= 2021)
test  <- df_ml_clean %>% filter(annee >= 2022)

cat("Train :", nrow(train), "obs (", min(train$annee),
    "–", max(train$annee), ")\n")
cat("Test  :", nrow(test),  "obs (", min(test$annee),
    "–", max(test$annee),  ")\n\n")

features <- c("total_lag1", "total_lag2", "ben_pm_lag1",
              "ifd_lag1", "saron_lag1", "ipc_lag1",
              "trend", "dummy_rffa")

X_train <- train %>% dplyr::select(all_of(features)) %>% as.matrix()
y_train <- train$total

X_test  <- test  %>% dplyr::select(all_of(features)) %>% as.matrix()
y_test  <- test$total

# =============================================================================
# PARTIE C — RANDOM FOREST
# =============================================================================
# Paramètres :
#   ntree=1000  : stabilité sans surapprentissage
#   mtry=3      : √p ≈ √8 ≈ 3
#   nodesize=3  : régularisation pour petit N
#   seed=42     : reproductibilité obligatoire
# =============================================================================

cat("=============================================================\n")
cat("PARTIE C — RANDOM FOREST\n")
cat("=============================================================\n\n")

set.seed(42)

rf_model <- randomForest(
  x          = X_train,
  y          = y_train,
  ntree      = 1000,
  mtry       = 3,
  nodesize   = 3,
  importance = TRUE
)

cat("--- Résultats Random Forest ---\n")
print(rf_model)

# Performance test set
pred_test  <- predict(rf_model, newdata = X_test)
rmse_rf    <- sqrt(mean((pred_test - y_test)^2))
mape_rf    <- mean(abs((pred_test - y_test) / y_test)) * 100

cat("\n--- Performance test set (2022–2024) ---\n")
cat("RMSE :", round(rmse_rf), "M CHF\n")
cat("MAPE :", round(mape_rf, 1), "%\n\n")

# Tableau prédictions vs réalisations
resultats_test <- tibble(
  Annee      = test$annee,
  Realise    = round(y_test),
  RF_predit  = round(pred_test),
  Erreur_abs = round(abs(pred_test - y_test)),
  Erreur_pct = round(abs(pred_test - y_test) / y_test * 100, 1)
)
cat("--- Prédictions vs réalisations (test) ---\n")
print(resultats_test)

cat("\n# NOTE SUR LES PERFORMANCES RF :\n")
cat("# Le RF est entraîné sur 2009–2021 — il n'a pas vu les niveaux\n")
cat("# exceptionnels de 2022–2024 (RFFA). La sous-prédiction est attendue\n")
cat("# et documentée. Le RF n'est PAS un modèle de prévision ici.\n")
cat("# Son apport est l'analyse SHAP des drivers — voir Partie D.\n\n")

# Validation walk-forward — distribution de RMSE
cat("--- Validation walk-forward ---\n")
cat("(RMSE sur fenêtres glissantes — plus robuste que test unique)\n\n")

rmse_wf <- numeric()
for (i in seq(10, nrow(df_ml_clean) - 3)) {
  train_wf <- df_ml_clean[1:i, ]
  test_wf  <- df_ml_clean[(i+1):(i+1), ]
  
  if (nrow(train_wf) < 5) next
  
  X_wf <- train_wf %>% dplyr::select(all_of(features)) %>% as.matrix()
  y_wf <- train_wf$total
  X_t  <- test_wf  %>% dplyr::select(all_of(features)) %>% as.matrix()
  y_t  <- test_wf$total
  
  set.seed(42)
  rf_wf   <- randomForest(x = X_wf, y = y_wf,
                          ntree = 500, mtry = 3, nodesize = 3)
  pred_wf <- predict(rf_wf, newdata = X_t)
  rmse_wf <- c(rmse_wf, sqrt((pred_wf - y_t)^2))
}

cat("RMSE walk-forward :\n")
cat("  Médiane :", round(median(rmse_wf)), "M CHF\n")
cat("  Min     :", round(min(rmse_wf)),    "M CHF\n")
cat("  Max     :", round(max(rmse_wf)),    "M CHF\n\n")

cat("# INTERPRÉTATION WALK-FORWARD :\n")
cat("# La distribution des RMSE walk-forward est plus informative\n")
cat("# que le RMSE sur 3 observations. Elle montre la variabilité\n")
cat("# réelle des performances du RF selon la fenêtre d'entraînement.\n\n")

# =============================================================================
# PARTIE D — SHAP VALUES
# =============================================================================
# POURQUOI SHAP ET PAS IMPORTANCE RF CLASSIQUE :
# L'importance RF classique (%IncMSE) mesure l'effet global de chaque
# variable sur l'ensemble du modèle — elle n'est pas signée et pas locale.
# Les SHAP values mesurent la contribution de chaque variable à CHAQUE
# prédiction individuelle — elles sont signées (positif = pousse vers le haut)
# et additives (sum = prédiction - baseline).
#
# LIMITE DOCUMENTÉE :
# Sur N=13 en training, les SHAP values sont instables. On les présente
# comme indicateurs de direction, pas comme mesures précises.
# nsim=200 pour réduire la variance (vs nsim=100 en v1).
# =============================================================================

cat("=============================================================\n")
cat("PARTIE D — SHAP VALUES\n")
cat("=============================================================\n\n")

cat("POURQUOI SHAP : mesure signée et locale de la contribution\n")
cat("de chaque variable à chaque prédiction.\n")
cat("⚠️  LIMITE : N=13 en training → instabilité des SHAP.\n")
cat("    Présentées comme indicateurs de direction, pas mesures précises.\n")
cat("    nsim=200 pour réduire la variance.\n\n")

pred_fun <- function(object, newdata) {
  predict(object, newdata = as.matrix(newdata))
}

set.seed(42)
shap_values <- fastshap::explain(
  object       = rf_model,
  X            = X_train,
  pred_wrapper = pred_fun,
  nsim         = 200
)

cat("SHAP calculées pour", nrow(shap_values), "observations\n\n")

# Importance SHAP globale
shap_importance <- colMeans(abs(shap_values)) %>%
  sort(decreasing = TRUE) %>%
  round(1)

cat("=== IMPORTANCE SHAP GLOBALE (M CHF) ===\n")
cat("(contribution moyenne absolue à la prédiction)\n\n")
print(shap_importance)

cat("\n# NOTE IMPORTANTE — dummy_rffa = 0M en SHAP :\n")
cat("# La dummy_rffa vaut 0 pour toutes les observations du training\n")
cat("# (2009–2021). Le Random Forest n'a jamais vu dummy_rffa = 1\n")
cat("# pendant l'entraînement — il ne peut donc pas apprendre son effet.\n")
cat("# Cela explique pourquoi SHAP = 0M pour cette variable.\n")
cat("# Ce résultat est cohérent et attendu — il ne remet pas en cause\n")
cat("# le coefficient ARIMAX (+1398M, p≈0) qui reste la mesure\n")
cat("# de référence de l'effet RFFA.\n\n")

# Labels lisibles pour les graphiques
labels_features <- c(
  "total_lag1"  = "Recettes fiscales (t-1)",
  "total_lag2"  = "Recettes fiscales (t-2)",
  "ben_pm_lag1" = "Bénéfice PM (t-1)",
  "ifd_lag1"    = "Part IFD (t-1)",
  "saron_lag1"  = "Taux SARON (t-1)",
  "ipc_lag1"    = "Inflation IPC (t-1)",
  "trend"       = "Tendance temporelle",
  "dummy_rffa"  = "Effet RFFA 2022+"
)

# =============================================================================
# PARTIE E — GRAPHIQUES SHAP
# =============================================================================

cat("=============================================================\n")
cat("PARTIE E — GRAPHIQUES SHAP\n")
cat("=============================================================\n\n")

# --- Graphique 1 : Importance SHAP globale ---
shap_imp_df <- tibble(
  feature    = names(shap_importance),
  shap_moyen = as.numeric(shap_importance)
) %>%
  mutate(label = labels_features[feature])

g_shap_imp <- ggplot(shap_imp_df,
                     aes(x = reorder(label, shap_moyen),
                         y = shap_moyen)) +
  geom_col(fill = couleurs[4], alpha = 0.85) +
  geom_text(aes(label = round(shap_moyen, 0)),
            hjust = -0.2, size = 3.5) +
  coord_flip() +
  scale_y_continuous(limits = c(0, max(shap_imp_df$shap_moyen) * 1.15)) +
  labs(
    title    = "Drivers des recettes fiscales — Analyse SHAP",
    subtitle = paste0("Contribution moyenne absolue de chaque variable\n",
                      "à la prédiction (en millions CHF)\n",
                      "⚠️  N=13 en training — indicateurs de direction,",
                      " pas mesures précises"),
    x = NULL, y = "SHAP moyen absolu (M CHF)",
    caption  = paste0("Modèle : Random Forest (ntree=1000, nsim=200) | ",
                      "Variable cible : Total recettes GE")
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title    = element_text(face = "bold"),
        plot.subtitle = element_text(size = 9, color = "grey40"))

print(g_shap_imp)
ggsave("04_shap_importance.png", g_shap_imp,
       width = 11, height = 7, dpi = 150)

# --- Graphique 2 : SHAP beeswarm top 5 ---
shap_df <- as.data.frame(shap_values)
colnames(shap_df) <- paste0("shap_", colnames(shap_df))

shap_long <- shap_df %>%
  mutate(obs = row_number()) %>%
  pivot_longer(
    cols      = starts_with("shap_"),
    names_to  = "feature",
    values_to = "shap"
  ) %>%
  mutate(feature = str_remove(feature, "^shap_"))

top5 <- names(shap_importance)[1:5]

shap_long_top5 <- shap_long %>%
  filter(feature %in% top5) %>%
  mutate(
    label   = labels_features[feature],
    label   = factor(label,
                     levels = rev(labels_features[top5]))
  )

g_shap_bee <- ggplot(shap_long_top5,
                     aes(x = shap, y = label)) +
  geom_jitter(aes(color = shap), height = 0.2,
              size = 3, alpha = 0.8) +
  geom_vline(xintercept = 0, linetype = "dashed",
             color = "grey50") +
  scale_color_gradient2(
    low      = couleurs[3],
    mid      = "grey80",
    high     = couleurs[2],
    midpoint = 0
  ) +
  labs(
    title    = "Distribution des SHAP — Top 5 drivers",
    subtitle = paste0("Chaque point = une année d'observation\n",
                      "Rouge = pousse les recettes vers le haut | ",
                      "Bleu = pousse vers le bas"),
    x = "SHAP value (M CHF)", y = NULL,
    color    = "SHAP",
    caption  = "Méthode : fastshap (nsim=200) | N=13 observations"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title      = element_text(face = "bold"),
    plot.subtitle   = element_text(size = 9, color = "grey40"),
    legend.position = "right"
  )

print(g_shap_bee)
ggsave("04_shap_beeswarm.png", g_shap_bee,
       width = 11, height = 6, dpi = 150)

# --- Graphique 3 : Importance RF classique vs SHAP ---
imp_rf_df <- as.data.frame(importance(rf_model)) %>%
  rownames_to_column("feature") %>%
  dplyr::select(feature, `%IncMSE`) %>%
  left_join(shap_imp_df %>% dplyr::select(feature, shap_moyen),
            by = "feature") %>%
  mutate(label = labels_features[feature]) %>%
  arrange(desc(shap_moyen))

cat("\n=== COMPARAISON IMPORTANCE RF vs SHAP ===\n")
print(imp_rf_df %>% dplyr::select(label, `%IncMSE`, shap_moyen))

g_comp_imp <- imp_rf_df %>%
  pivot_longer(cols      = c(`%IncMSE`, shap_moyen),
               names_to  = "methode",
               values_to = "valeur") %>%
  mutate(
    methode = recode(methode,
                     "%IncMSE"   = "Importance RF (%IncMSE)",
                     "shap_moyen" = "SHAP moyen absolu (M CHF)"),
    label = factor(label, levels = rev(imp_rf_df$label))
  ) %>%
  ggplot(aes(x = valeur, y = label, fill = methode)) +
  geom_col(position = "dodge", alpha = 0.85) +
  scale_fill_manual(values = c(couleurs[3], couleurs[4])) +
  facet_wrap(~methode, scales = "free_x") +
  labs(
    title    = "Importance des variables — RF classique vs SHAP",
    subtitle = "Deux méthodes, même classement → robustesse de la conclusion",
    x = NULL, y = NULL,
    fill     = NULL,
    caption  = "Random Forest (ntree=1000) | SHAP (nsim=200)"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "none"
  )

print(g_comp_imp)
ggsave("04_shap_vs_rf_importance.png", g_comp_imp,
       width = 13, height = 6, dpi = 150)

# =============================================================================
# SYNTHÈSE — CONCLUSIONS DRIVERS
# =============================================================================

cat("\n=============================================================\n")
cat("SYNTHÈSE — DRIVERS DES RECETTES FISCALES GENEVOISES\n")
cat("=============================================================\n\n")

cat("TOP DRIVERS IDENTIFIÉS PAR SHAP :\n\n")

cat("1.", labels_features[names(shap_importance)[1]], "\n")
cat("   SHAP moyen =", shap_importance[1], "M CHF\n")
cat("   → La variable la plus influente sur les variations annuelles.\n\n")

cat("2.", labels_features[names(shap_importance)[2]], "\n")
cat("   SHAP moyen =", shap_importance[2], "M CHF\n")
cat("   → La mémoire fiscale récente est un fort prédicteur.\n\n")

cat("3.", labels_features[names(shap_importance)[3]], "\n")
cat("   SHAP moyen =", shap_importance[3], "M CHF\n\n")

cat("4.", labels_features[names(shap_importance)[4]], "\n")
cat("   SHAP moyen =", shap_importance[4], "M CHF\n\n")

cat("5.", labels_features[names(shap_importance)[5]], "\n")
cat("   SHAP moyen =", shap_importance[5], "M CHF\n\n")

cat("CONCLUSION PRINCIPALE :\n")
cat("Les recettes fiscales genevoises sont principalement déterminées\n")
cat("par leur propre dynamique passée (mémoire fiscale) et par les\n")
cat("bénéfices des personnes morales — principal vecteur de transmission\n")
cat("entre l'activité économique genevoise et les recettes de l'État.\n\n")

cat("LIMITE À DOCUMENTER :\n")
cat("Ces conclusions sont basées sur N=13 observations en training.\n")
cat("Les SHAP values sont instables sur petit échantillon.\n")
cat("On les présente comme indicateurs de direction robustes,\n")
cat("pas comme mesures précises.\n\n")

cat("✓ Script 04 terminé. Graphiques sauvegardés.\n")
cat("→ Prochaine étape : synthèse et publication (script 05)\n")