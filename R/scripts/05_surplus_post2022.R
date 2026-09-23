# =============================================================================
# PROJET : ANALYSE & PREVISION DES RECETTES FISCALES GENEVOISES
# Script  : 05_surplus_post2022.R
# Objet   : mesurer le surplus de recettes 2022-2024 par rapport a la
#           tendance 2007-2021 (contrefactuel explicite)
# =============================================================================
#
# POURQUOI CE SCRIPT REMPLACE L'ANCIEN 05 (bootstrap + BSTS) :
# - Dans l'ARIMAX (0,1,0), la dummy en palier devient une impulsion unique
#   en differences : son coefficient (+1398M) recopie exactement la hausse
#   observee en 2022. Ce n'est pas une estimation d'effet.
# - Le bootstrap mesurait un autre objet (ecart de croissance annuelle).
# - Le BSTS reposait sur la meme dummy et le meme saut : pas une
#   confirmation independante.
#
# APPROCHE RETENUE :
# On projette la tendance 2007-2021 sur 2022-2024 et on mesure l'ecart
# avec les valeurs observees. Deux contrefactuels sont compares pour
# montrer la sensibilite au choix de tendance :
#   1. Marche aleatoire avec derive (coherent avec la serie I(1), script 02)
#   2. Tendance lineaire deterministe (OLS sur 2007-2021)
# Cet ecart est descriptif : il ne constitue pas une estimation causale
# de l'effet de la RFFA.
# =============================================================================

library(tidyverse)
library(forecast)
library(scales)

if (!exists("df")) {
  stop("L'objet 'df' n'est pas en memoire. Relancer le script 01 d'abord.")
}

annee_rupture <- 2022
pre  <- df$annee <  annee_rupture
post <- df$annee >= annee_rupture
annees_post <- df$annee[post]
h <- sum(post)

# -----------------------------------------------------------------------------
# 1. FONCTION : ecart observe - contrefactuel pour une serie
# -----------------------------------------------------------------------------
ecart_contrefactuel <- function(x) {
  # Contrefactuel 1 : marche aleatoire avec derive
  y_pre <- ts(x[pre], start = min(df$annee))
  fc    <- rwf(y_pre, h = h, drift = TRUE, level = 95)
  cf_drift <- as.numeric(fc$mean)

  # Contrefactuel 2 : tendance lineaire deterministe
  fit_lin <- lm(x[pre] ~ df$annee[pre])
  cf_lin  <- coef(fit_lin)[1] + coef(fit_lin)[2] * annees_post

  tibble(
    annee    = annees_post,
    observe  = x[post],
    cf_drift = cf_drift,
    cf_lo95  = as.numeric(fc$lower),
    cf_hi95  = as.numeric(fc$upper),
    cf_lin   = as.numeric(cf_lin),
    ecart_drift = x[post] - cf_drift,
    ecart_lin   = x[post] - as.numeric(cf_lin)
  )
}

# -----------------------------------------------------------------------------
# 2. TOTAL DES RECETTES
# -----------------------------------------------------------------------------
res_total <- ecart_contrefactuel(df$total)

cat("=============================================================\n")
cat("SURPLUS POST-2022 : TOTAL DES RECETTES (M CHF)\n")
cat("=============================================================\n")
print(res_total %>% mutate(across(-annee, round)))

ecart_moy_drift <- mean(res_total$ecart_drift)
ecart_moy_lin   <- mean(res_total$ecart_lin)
hors_ic <- sum(res_total$observe > res_total$cf_hi95)

cat("\nEcart moyen 2022-2024 :\n")
cat("  Contrefactuel derive   :", round(ecart_moy_drift), "M CHF/an\n")
cat("  Contrefactuel lineaire :", round(ecart_moy_lin), "M CHF/an\n")
cat("  Annees au-dessus de l'IC 95% (derive) :", hors_ic, "sur", h, "\n\n")

# -----------------------------------------------------------------------------
# 3. DECOMPOSITION PAR COMPOSANTE
# -----------------------------------------------------------------------------
composantes <- c(
  pp_total     = "Personnes physiques",
  pm_total     = "Personnes morales",
  ifd          = "Part cantonale IFD",
  enreg_timbre = "Enregistrement et timbre",
  successions  = "Successions"
)

decomp <- map_dfr(names(composantes), function(v) {
  r <- ecart_contrefactuel(df[[v]])
  tibble(
    composante  = composantes[[v]],
    ecart_drift = mean(r$ecart_drift),
    ecart_lin   = mean(r$ecart_lin)
  )
})

# Residu : ecart du total non explique par les composantes listees
decomp <- bind_rows(
  decomp,
  tibble(
    composante  = "Autres (residu)",
    ecart_drift = ecart_moy_drift - sum(decomp$ecart_drift),
    ecart_lin   = ecart_moy_lin   - sum(decomp$ecart_lin)
  )
) %>%
  mutate(part_drift = ecart_drift / ecart_moy_drift * 100)

cat("=============================================================\n")
cat("DECOMPOSITION DE L'ECART MOYEN PAR COMPOSANTE (M CHF/an)\n")
cat("=============================================================\n")
print(decomp %>% mutate(across(where(is.numeric), ~ round(., 0))))

cat("\n# LECTURE :\n")
cat("# Le surplus post-2022 provient majoritairement des personnes\n")
cat("# physiques. La RFFA (en vigueur depuis 2020, reforme de l'imposition\n")
cat("# des entreprises) peut concerner au mieux la part personnes morales.\n")
cat("# Aucune attribution causale n'est possible avec ces donnees.\n\n")

# -----------------------------------------------------------------------------
# 4. FIGURES
# -----------------------------------------------------------------------------
figures_dir <- file.path("R", "figures")
if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)

# Point de raccord 2021 pour que les contrefactuels partent de la serie
raccord <- df %>% filter(annee == annee_rupture - 1) %>% pull(total)
raccord_lin <- {
  fit <- lm(df$total[pre] ~ df$annee[pre])
  as.numeric(coef(fit)[1] + coef(fit)[2] * (annee_rupture - 1))
}

cf_plot <- bind_rows(
  tibble(annee = annee_rupture - 1, valeur = raccord,
         type = "Tendance avec dérive"),
  tibble(annee = res_total$annee, valeur = res_total$cf_drift,
         type = "Tendance avec dérive"),
  tibble(annee = annee_rupture - 1, valeur = raccord_lin,
         type = "Tendance linéaire"),
  tibble(annee = res_total$annee, valeur = res_total$cf_lin,
         type = "Tendance linéaire")
)

ic_plot <- bind_rows(
  tibble(annee = annee_rupture - 1, lo = raccord, hi = raccord),
  tibble(annee = res_total$annee, lo = res_total$cf_lo95, hi = res_total$cf_hi95)
)

g_cf <- ggplot() +
  geom_ribbon(data = ic_plot, aes(x = annee, ymin = lo, ymax = hi),
              fill = "#2980B9", alpha = 0.15) +
  geom_segment(data = res_total,
               aes(x = annee, xend = annee, y = cf_drift, yend = observe),
               colour = "#E74C3C", linewidth = 0.8,
               arrow = arrow(length = unit(0.15, "cm"))) +
  geom_line(data = cf_plot, aes(annee, valeur, linetype = type),
            colour = "#2980B9", linewidth = 1) +
  geom_line(data = df, aes(annee, total), colour = "#2C3E50", linewidth = 1.3) +
  geom_point(data = df, aes(annee, total), colour = "#2C3E50", size = 2) +
  geom_vline(xintercept = annee_rupture - 0.5, linetype = "dotted",
             colour = "grey50") +
  annotate("text", x = 2019.6, y = 8900, hjust = 1,
           label = paste0("Écart moyen : +", comma(round(ecart_moy_drift),
                                                   big.mark = "'"),
                          " M/an (dérive)\n+",
                          comma(round(ecart_moy_lin), big.mark = "'"),
                          " M/an (linéaire)"),
           size = 3.3, colour = "#E74C3C") +
  scale_x_continuous(breaks = seq(2007, 2024, 2)) +
  scale_y_continuous(labels = label_number(scale = 1e-3, suffix = " Mrd CHF",
                                           accuracy = 1)) +
  scale_linetype_manual(values = c("Tendance avec dérive" = "dashed",
                                   "Tendance linéaire" = "dotdash")) +
  labs(
    title    = "Recettes 2022-2024 comparées à la tendance 2007-2021",
    subtitle = paste0("Flèches : écart observé moins tendance avec dérive | ",
                      "Zone bleue : IC 95 % de cette tendance"),
    x = NULL, y = NULL, linetype = "Contrefactuel",
    caption  = "Source : OCSTAT T18.02.1.15 | Écart descriptif, sans attribution causale"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title = element_text(face = "bold"))

ggsave(file.path(figures_dir, "05_surplus_post2022.png"), g_cf,
       width = 12, height = 6, dpi = 150)

g_decomp <- decomp %>%
  mutate(composante = fct_reorder(composante, ecart_drift)) %>%
  ggplot(aes(x = ecart_drift, y = composante,
             fill = ecart_drift > 0)) +
  geom_col(alpha = 0.85, width = 0.7) +
  geom_text(aes(label = paste0(ifelse(ecart_drift > 0, "+", ""),
                               round(ecart_drift), " M"),
                hjust = ifelse(ecart_drift > 0, -0.1, 1.1)),
            size = 3.5) +
  geom_vline(xintercept = 0, colour = "grey40") +
  scale_fill_manual(values = c(`TRUE` = "#27AE60", `FALSE` = "#E74C3C"),
                    guide = "none") +
  scale_x_continuous(expand = expansion(mult = 0.2)) +
  labs(
    title    = "D'où vient le surplus post-2022 ?",
    subtitle = paste0("Écart moyen 2022-2024 par rapport à la tendance ",
                      "2007-2021, par composante (M CHF/an)"),
    x = NULL, y = NULL,
    caption  = "Source : OCSTAT T18.02.1.15 | Contrefactuel : marche aléatoire avec dérive"
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(figures_dir, "05_decomposition_surplus.png"), g_decomp,
       width = 10, height = 5, dpi = 150)

cat("Figures sauvegardees dans", figures_dir, ":\n")
cat("  05_surplus_post2022.png\n  05_decomposition_surplus.png\n")
