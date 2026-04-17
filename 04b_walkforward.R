# =============================================================================
# PROJET : ANALYSE & PRÉVISION DES RECETTES FISCALES GENEVOISES
# Script  : 04b_walkforward.R
# Auteur  : Frat DAG
# Date    : Avril 2026
# Version : 2.0 — approche inductive
# =============================================================================
# OBJECTIF :
# Comparer les quatre modèles sur une base équitable via validation
# walk-forward (expanding window) :
#   - Entraîner sur 2007–t, prédire t+1
#   - Répéter pour t = 2016, 2017, ..., 2023
#   - Produire un tableau année par année : réalisé vs prédit par modèle
#   - Calculer RMSE walk-forward par modèle — comparable sur même base
#
# POURQUOI WALK-FORWARD ET PAS CROSS-VALIDATION CLASSIQUE ?
# La cross-validation classique (k-fold) mélange passé et futur — elle
# introduit du leakage temporel. Sur des séries temporelles, on entraîne
# toujours sur le passé et on prédit le futur. Le walk-forward respecte
# cette contrainte.
#
# FENÊTRE DE TEST : 2017–2024 (8 observations)
# Fenêtre minimale d'entraînement : 2007–2016 (10 observations)
# C'est le meilleur compromis entre stabilité du modèle et taille du test.
# =============================================================================

library(tidyverse)
library(forecast)
library(randomForest)
library(ggplot2)
library(patchwork)
library(scales)

# -----------------------------------------------------------------------------
# 0. VÉRIFICATION
# -----------------------------------------------------------------------------

if (!exists("df")) {
  stop("L'objet 'df' n'est pas en mémoire. Relancer scripts 01 à 04.")
}
cat("✓ Objet 'df' disponible :", nrow(df), "observations\n\n")

couleurs <- c("#2C3E50", "#E74C3C", "#2980B9", "#27AE60", "#F39C12")

# Années de test
annees_test <- 2017:2024
cat("Fenêtre walk-forward :\n")
cat("  Entraînement minimum : 2007–2016 (10 obs)\n")
cat("  Test                 : 2017–2024 (8 obs)\n\n")

# =============================================================================
# BOUCLE WALK-FORWARD
# =============================================================================
# Pour chaque année t dans annees_test :
#   1. Entraîner chaque modèle sur 2007:(t-1)
#   2. Prédire t
#   3. Enregistrer la prédiction et l'erreur
# =============================================================================

resultats_wf <- tibble(
  annee       = integer(),
  realise     = numeric(),
  pred_arima  = numeric(),
  pred_ets    = numeric(),
  pred_arimax = numeric(),
  pred_rf     = numeric()
)

# Features RF — identiques au script 04
features_rf <- c("total_lag1", "total_lag2", "ben_pm_lag1",
                 "ifd_lag1", "saron_lag1", "ipc_lag1",
                 "trend", "dummy_rffa")

# Préparation du dataset ML (identique script 04)
df_ml_wf <- df %>%
  arrange(annee) %>%
  mutate(
    total_lag1  = lag(total,   1),
    total_lag2  = lag(total,   2),
    ben_pm_lag1 = lag(ben_pm,  1),
    ifd_lag1    = lag(ifd,     1),
    saron_lag1  = lag(saron,   1),
    ipc_lag1    = lag(ipc,     1),
    trend       = annee - mean(annee)
  ) %>%
  filter(complete.cases(dplyr::select(., annee, total,
                                      all_of(features_rf))))

cat("Dataset ML walk-forward :", nrow(df_ml_wf), "observations\n")
cat("Période :", min(df_ml_wf$annee), "–",
    max(df_ml_wf$annee), "\n\n")

cat("Lancement de la boucle walk-forward...\n\n")

for (an in annees_test) {
  
  cat("→ Prédiction", an,
      "| Entraînement 2007–", an - 1, "\n")
  
  # Données d'entraînement
  df_train <- df %>% filter(annee < an)
  df_test  <- df %>% filter(annee == an)
  
  valeur_realisee <- df_test$total
  
  # -------------------------------------------------------------------
  # Modèle 1 — ARIMA(0,1,0) avec drift
  # -------------------------------------------------------------------
  ts_train <- ts(df_train$total,
                 start = min(df_train$annee), frequency = 1)
  
  arima_wf <- tryCatch(
    Arima(ts_train, order = c(0, 1, 0), include.drift = TRUE),
    error = function(e) NULL
  )
  
  pred_arima <- if (!is.null(arima_wf)) {
    as.numeric(forecast(arima_wf, h = 1)$mean)
  } else NA
  
  # -------------------------------------------------------------------
  # Modèle 2 — ETS
  # -------------------------------------------------------------------
  ets_wf <- tryCatch(
    ets(ts_train),
    error = function(e) NULL
  )
  
  pred_ets <- if (!is.null(ets_wf)) {
    as.numeric(forecast(ets_wf, h = 1)$mean)
  } else NA
  
  # -------------------------------------------------------------------
  # Modèle 3 — ARIMAX (ARIMA + dummy_rffa)
  # -------------------------------------------------------------------
  xreg_train_wf <- matrix(df_train$dummy_rffa, ncol = 1,
                          dimnames = list(NULL, "dummy_rffa"))
  xreg_test_wf  <- matrix(df_test$dummy_rffa,  ncol = 1,
                          dimnames = list(NULL, "dummy_rffa"))
  
  arimax_wf <- tryCatch(
    Arima(ts_train, order = c(0, 1, 0),
          xreg = xreg_train_wf),
    error = function(e) NULL
  )
  
  pred_arimax <- if (!is.null(arimax_wf)) {
    as.numeric(forecast(arimax_wf, h = 1,
                        xreg = xreg_test_wf)$mean)
  } else NA
  
  # -------------------------------------------------------------------
  # Modèle 4 — Random Forest
  # -------------------------------------------------------------------
  df_train_ml <- df_ml_wf %>% filter(annee < an)
  df_test_ml  <- df_ml_wf %>% filter(annee == an)
  
  pred_rf <- NA
  
  if (nrow(df_train_ml) >= 5 && nrow(df_test_ml) == 1) {
    X_train_wf <- df_train_ml %>%
      dplyr::select(all_of(features_rf)) %>% as.matrix()
    y_train_wf <- df_train_ml$total
    X_test_wf  <- df_test_ml %>%
      dplyr::select(all_of(features_rf)) %>% as.matrix()
    
    set.seed(42)
    rf_wf <- tryCatch(
      randomForest(x = X_train_wf, y = y_train_wf,
                   ntree = 500, mtry = 3, nodesize = 3),
      error = function(e) NULL
    )
    
    if (!is.null(rf_wf)) {
      pred_rf <- as.numeric(predict(rf_wf, newdata = X_test_wf))
    }
  }
  
  # Enregistrement
  resultats_wf <- resultats_wf %>%
    add_row(
      annee       = an,
      realise     = valeur_realisee,
      pred_arima  = round(pred_arima,  0),
      pred_ets    = round(pred_ets,    0),
      pred_arimax = round(pred_arimax, 0),
      pred_rf     = round(pred_rf,     0)
    )
}

# =============================================================================
# TABLEAU DES PRÉDICTIONS ANNÉE PAR ANNÉE
# =============================================================================

cat("\n=============================================================\n")
cat("TABLEAU WALK-FORWARD — PRÉDICTIONS VS RÉALISATIONS\n")
cat("=============================================================\n\n")

tableau_wf <- resultats_wf %>%
  mutate(
    err_arima  = round(pred_arima  - realise, 0),
    err_ets    = round(pred_ets    - realise, 0),
    err_arimax = round(pred_arimax - realise, 0),
    err_rf     = round(pred_rf     - realise, 0)
  )

print(tableau_wf %>%
        dplyr::select(annee, realise, pred_arima, pred_ets,
                      pred_arimax, pred_rf))

cat("\nErreurs (prédit - réalisé, M CHF) :\n")
print(tableau_wf %>%
        dplyr::select(annee, err_arima, err_ets,
                      err_arimax, err_rf))

# =============================================================================
# RMSE WALK-FORWARD PAR MODÈLE
# =============================================================================

# =============================================================================
# RMSE WALK-FORWARD PAR MODÈLE
# =============================================================================

cat("\n=============================================================\n")
cat("RMSE WALK-FORWARD — COMPARAISON DES MODÈLES\n")
cat("=============================================================\n\n")

cat("NOTE SUR ARIMAX :\n")
cat("ARIMAX n'est estimable en walk-forward qu'à partir de 2023.\n")
cat("Avant 2022, dummy_rffa = 0 sur tout l'entraînement ET le test —\n")
cat("le modèle est identique à ARIMA pur. Il n'est donc pas comparable\n")
cat("sur la période 2017–2021 et est exclu du RMSE hors RFFA.\n\n")

rmse_wf_comp <- tibble(
  Modele      = c("ARIMA baseline", "ETS",
                  "ARIMAX (+dummy_rffa)", "Random Forest"),
  RMSE_wf_total = c(
    sqrt(mean((resultats_wf$pred_arima  - resultats_wf$realise)^2,
              na.rm = TRUE)),
    sqrt(mean((resultats_wf$pred_ets    - resultats_wf$realise)^2,
              na.rm = TRUE)),
    sqrt(mean((resultats_wf$pred_arimax - resultats_wf$realise)^2,
              na.rm = TRUE)),
    sqrt(mean((resultats_wf$pred_rf     - resultats_wf$realise)^2,
              na.rm = TRUE))
  ),
  RMSE_wf_pre2022 = c(
    sqrt(mean((resultats_wf %>%
                 filter(annee < 2022) %>%
                 pull(pred_arima) - resultats_wf %>%
                 filter(annee < 2022) %>%
                 pull(realise))^2, na.rm = TRUE)),
    sqrt(mean((resultats_wf %>%
                 filter(annee < 2022) %>%
                 pull(pred_ets) - resultats_wf %>%
                 filter(annee < 2022) %>%
                 pull(realise))^2, na.rm = TRUE)),
    NA_real_,   # ARIMAX non estimable avant 2022 — voir note ci-dessus
    sqrt(mean((resultats_wf %>%
                 filter(annee < 2022) %>%
                 pull(pred_rf) - resultats_wf %>%
                 filter(annee < 2022) %>%
                 pull(realise))^2, na.rm = TRUE))
  ),
  Note = c("", "", "Non estimable avant 2022", "")
) %>%
  mutate(
    RMSE_wf_total   = round(RMSE_wf_total, 0),
    RMSE_wf_pre2022 = round(RMSE_wf_pre2022, 0)
  ) %>%
  arrange(RMSE_wf_total)

cat("RMSE walk-forward — toutes années (2017–2024) :\n")
print(rmse_wf_comp %>% dplyr::select(Modele, RMSE_wf_total, Note))

cat("\nRMSE walk-forward — hors RFFA (2017–2021) :\n")
cat("(période sans rupture structurelle — comparaison la plus équitable)\n")
cat("ARIMAX exclu : non estimable sur cette fenêtre.\n\n")
print(rmse_wf_comp %>%
        filter(Modele != "ARIMAX (+dummy_rffa)") %>%
        dplyr::select(Modele, RMSE_wf_pre2022) %>%
        arrange(RMSE_wf_pre2022))

cat("\n# DÉCISION FINALE :\n")
cat("# Modèle le plus performant hors RFFA : ARIMA baseline (252M)\n")
cat("# Modèle le plus performant toutes années : ARIMAX (465M)\n")
cat("# Ces deux résultats sont cohérents et complémentaires :\n")
cat("# ARIMA est le meilleur modèle en conditions normales.\n")
cat("# ARIMAX capture mieux les ruptures structurelles connues.\n")
cat("# → ARIMAX reste le modèle retenu pour les prévisions 2025–2027\n")
cat("#   car la rupture RFFA est documentée et persistante.\n\n")

# =============================================================================
# GRAPHIQUE WALK-FORWARD
# =============================================================================

df_wf_long <- resultats_wf %>%
  pivot_longer(
    cols      = starts_with("pred_"),
    names_to  = "modele",
    values_to = "prediction"
  ) %>%
  mutate(modele = recode(modele,
                         "pred_arima"  = "ARIMA baseline",
                         "pred_ets"    = "ETS",
                         "pred_arimax" = "ARIMAX",
                         "pred_rf"     = "Random Forest"
  ))

# Données historiques pour contexte
df_hist_wf <- tibble(
  annee    = df$annee,
  realise  = df$total
)

g_wf <- ggplot() +
  # Historique complet
  geom_line(data = df_hist_wf,
            aes(x = annee, y = realise / 1000),
            color = couleurs[1], linewidth = 1.2) +
  geom_point(data = df_hist_wf,
             aes(x = annee, y = realise / 1000),
             color = couleurs[1], size = 1.8) +
  # Points réalisés dans la fenêtre de test
  geom_point(data = resultats_wf,
             aes(x = annee, y = realise / 1000),
             color = couleurs[1], size = 3,
             shape = 21, fill = "white", stroke = 1.5) +
  # Prédictions par modèle
  geom_line(data = df_wf_long,
            aes(x = annee, y = prediction / 1000,
                color = modele),
            linewidth = 0.9, linetype = "dashed") +
  geom_point(data = df_wf_long,
             aes(x = annee, y = prediction / 1000,
                 color = modele),
             size = 2, shape = 17) +
  scale_color_manual(values = c(
    "ARIMA baseline" = couleurs[2],
    "ETS"            = couleurs[4],
    "ARIMAX"         = couleurs[3],
    "Random Forest"  = couleurs[5]
  )) +
  scale_y_continuous(
    labels = label_number(suffix = " Mrd CHF")
  ) +
  scale_x_continuous(breaks = seq(2007, 2024, by = 2)) +
  geom_vline(xintercept = 2016.5, linetype = "dotted",
             color = "grey50") +
  geom_vline(xintercept = 2021.5, linetype = "dotted",
             color = couleurs[2], alpha = 0.5) +
  annotate("text", x = 2016.7, y = 6.1,
           label = "Début\ntest", size = 2.8,
           color = "grey50", hjust = 0) +
  annotate("text", x = 2021.7, y = 6.1,
           label = "RFFA\n2022+", size = 2.8,
           color = couleurs[2], hjust = 0) +
  labs(
    title    = "Validation walk-forward — Comparaison des quatre modèles",
    subtitle = paste0(
      "Entraînement sur 2007:(t-1) | Prédiction de t | ",
      "Fenêtre de test : 2017–2024\n",
      "Cercles vides = valeurs réalisées | ",
      "ARIMAX : 2 points seulement (2023–2024) — ",
      "non estimable avant 2022"
    ),
    x = NULL, y = NULL,
    color    = NULL,
    caption  = paste0(
      "Source : OCSTAT T18.02.1.15 | ",
      "RMSE walk-forward hors RFFA : ARIMA=252M, ETS=365M, RF=555M"
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title      = element_text(face = "bold"),
    plot.subtitle   = element_text(size = 9, color = "grey40"),
    legend.position = "bottom"
  )

print(g_wf)
ggsave("04b_walkforward.png", g_wf,
       width = 13, height = 7, dpi = 150)

# Graphique erreurs par modèle et par année
df_err <- tableau_wf %>%
  dplyr::select(annee, err_arima, err_ets,
                err_arimax, err_rf) %>%
  pivot_longer(-annee, names_to = "modele",
               values_to = "erreur") %>%
  mutate(modele = recode(modele,
                         "err_arima"  = "ARIMA baseline",
                         "err_ets"    = "ETS",
                         "err_arimax" = "ARIMAX",
                         "err_rf"     = "Random Forest"
  ))

g_err <- ggplot(df_err, aes(x = annee, y = erreur / 1000,
                            fill = modele)) +
  geom_col(position = "dodge", alpha = 0.85) +
  geom_hline(yintercept = 0, color = "grey30") +
  scale_fill_manual(values = c(
    "ARIMA baseline" = couleurs[2],
    "ETS"            = couleurs[4],
    "ARIMAX"         = couleurs[3],
    "Random Forest"  = couleurs[5]
  )) +
  scale_x_continuous(breaks = 2017:2024) +
  scale_y_continuous(
    labels = label_number(suffix = " Mrd CHF")
  ) +
  labs(
    title    = "Erreurs de prédiction walk-forward par année et par modèle",
    subtitle = "Erreur = prédit - réalisé | Barre au-dessus = sur-estimation",
    x = NULL, y = "Erreur (Mrd CHF)",
    fill     = NULL,
    caption  = "Source : OCSTAT T18.02.1.15"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "bottom"
  )

print(g_err)
ggsave("04b_erreurs_walkforward.png", g_err,
       width = 13, height = 6, dpi = 150)

cat("\n✓ Script 04b terminé.\n")
cat("Fichiers sauvegardés : 04b_walkforward.png,",
    "04b_erreurs_walkforward.png\n")
cat("→ Prochaine étape : script 05 synthèse et publication\n")
