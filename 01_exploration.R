# =============================================================================
# PROJET : ANALYSE & PRÉVISION DES RECETTES FISCALES GENEVOISES
# Script  : 01_exploration.R
# Auteur  : Frat DAG
# Date    : Avril 2026
# Version : 2.0 — approche inductive
# =============================================================================
# POINT DE DÉPART : on ne sait pas encore quels modèles on va utiliser.
# Ce script laisse les données poser les questions.
# Les questions identifiées ici détermineront le script 02.
# =============================================================================

# -----------------------------------------------------------------------------
# 0. PACKAGES
# -----------------------------------------------------------------------------

library(tidyverse)
library(scales)
library(patchwork)

# -----------------------------------------------------------------------------
# 1. SAISIE DES DONNÉES
# -----------------------------------------------------------------------------
# Source : OCSTAT T18.02.1.15 — Revenus d'impôts de l'État de Genève
# Unité  : millions de CHF, totaux annuels
# Période: 2007–2024 (N=18)
#
# NOTE NOMENCLATURE :
# On n'utilise PAS l'acronyme ICC — à Genève, ICC = Impôts Cantonaux et
# Communaux (terme générique). On utilise "ben_pm" pour l'impôt sur le
# bénéfice des personnes morales, conformément à la nomenclature OCSTAT.
# -----------------------------------------------------------------------------

fiscal <- tibble(
  annee = 2007:2024,
  
  # Impôts sur les personnes physiques
  pp_total   = c(3699.6, 3831.1, 3726.9, 3569.6, 3700.9,
                 3915, 3724, 3941, 3888, 3779, 4005, 4037,
                 4322, 4562, 4285, 5274, 5006, 5171),
  
  ir         = c(3221.0, 3379.0, 3182.9, 3031.9, 3113.1,
                 2521, 2581, 2831, 2647, 2540, 2530, 2622,
                 2802, 2992, 2510, 2919, 3046, 2963),
  
  fortune    = c(461.0, 433.0, 524.8, 512.1, 578.5,
                 614, 602, 696, 694, 710, 894, 810,
                 928, 953, 980, 1027, 1033, 1207),
  
  # Impôts sur les personnes morales
  # ben_pm = impôt sur le bénéfice des personnes morales (nomenclature OCSTAT)
  pm_total   = c(1246.1, 1302.1, 1183.1, 1080.6, 1240.5,
                 1354, 1448, 1465, 1391, 1474, 1420, 1772,
                 1639, 1350, 1684, 2045, 2600, 2108),
  
  ben_pm     = c(992.6, 1039.8, 945.2, 822.0, 980.9,
                 1082, 1151, 1157, 1099, 1165, 1093, 1429,
                 1292, 1019, 1416, 1813, 2387, 1925),
  
  cap_pm     = c(252.9, 259.3, 235.9, 253.6, 255.2,
                 271, 289, 298, 287, 305, 322, 327,
                 342, 311, 263, 215, 204, 183),
  
  # Autres impôts
  # enreg_timbre = "Produits de l'enregistrement et timbre" (nomenclature OCSTAT)
  # Note : agrège droits de mutation immobiliers, droits de timbre
  # et autres droits d'enregistrement — pas uniquement les droits de mutation
  enreg_timbre = c(184.4, 160.4, 217.6, 184.9, 203.2,
                   179, 160, 162, 185, 198, 217, 262,
                   216, 326, 328, 310, 271, 282),
  
  successions = c(98.5, 107.2, 308.4, 194.6, 98.6,
                  105, 132, 261, 147, 207, 152, 157,
                  195, 188, 187, 264, 324, 255),
  
  # Part cantonale à l'impôt fédéral direct
  ifd        = c(387.0, 362.9, 347.5, 370.6, 453.2,
                 396, 372, 399, 375, 367, 393, 473,
                 482, 566, 723, 813, 1011, 913),
  
  # Total
  total      = c(5970.9, 6157.2, 6213.5, 5818.6, 6121.4,
                 6407, 6278, 6577, 6461, 6528, 6641, 7173,
                 7363, 7454, 7871, 9269, 9734, 9269)
)

# -----------------------------------------------------------------------------
# 2. DONNÉES MACRO
# -----------------------------------------------------------------------------

# PIB nominal Genève (OFS — Comptes régionaux)
# Période : 2008–2022 (2022 = provisoire)
pib <- tibble(
  annee  = 2008:2022,
  pib_ge = c(47597, 46480, 48388, 48536, 49397, 50197,
             50311, 50042, 50365, 51443, 53900, 54591,
             52016, 56229, 61231)
)

# SARON mensuel → moyenne annuelle (BNS)
saron_m <- tibble(
  date = c(
    "2000-01","2000-02","2000-03","2000-04","2000-05","2000-06",
    "2000-07","2000-08","2000-09","2000-10","2000-11","2000-12",
    "2001-01","2001-02","2001-03","2001-04","2001-05","2001-06",
    "2001-07","2001-08","2001-09","2001-10","2001-11","2001-12",
    "2002-01","2002-02","2002-03","2002-04","2002-05","2002-06",
    "2002-07","2002-08","2002-09","2002-10","2002-11","2002-12",
    "2003-01","2003-02","2003-03","2003-04","2003-05","2003-06",
    "2003-07","2003-08","2003-09","2003-10","2003-11","2003-12",
    "2004-01","2004-02","2004-03","2004-04","2004-05","2004-06",
    "2004-07","2004-08","2004-09","2004-10","2004-11","2004-12",
    "2005-01","2005-02","2005-03","2005-04","2005-05","2005-06",
    "2005-07","2005-08","2005-09","2005-10","2005-11","2005-12",
    "2006-01","2006-02","2006-03","2006-04","2006-05","2006-06",
    "2006-07","2006-08","2006-09","2006-10","2006-11","2006-12",
    "2007-01","2007-02","2007-03","2007-04","2007-05","2007-06",
    "2007-07","2007-08","2007-09","2007-10","2007-11","2007-12",
    "2008-01","2008-02","2008-03","2008-04","2008-05","2008-06",
    "2008-07","2008-08","2008-09","2008-10","2008-11","2008-12",
    "2009-01","2009-02","2009-03","2009-04","2009-05","2009-06",
    "2009-07","2009-08","2009-09","2009-10","2009-11","2009-12",
    "2010-01","2010-02","2010-03","2010-04","2010-05","2010-06",
    "2010-07","2010-08","2010-09","2010-10","2010-11","2010-12",
    "2011-01","2011-02","2011-03","2011-04","2011-05","2011-06",
    "2011-07","2011-08","2011-09","2011-10","2011-11","2011-12",
    "2012-01","2012-02","2012-03","2012-04","2012-05","2012-06",
    "2012-07","2012-08","2012-09","2012-10","2012-11","2012-12",
    "2013-01","2013-02","2013-03","2013-04","2013-05","2013-06",
    "2013-07","2013-08","2013-09","2013-10","2013-11","2013-12",
    "2014-01","2014-02","2014-03","2014-04","2014-05","2014-06",
    "2014-07","2014-08","2014-09","2014-10","2014-11","2014-12",
    "2015-01","2015-02","2015-03","2015-04","2015-05","2015-06",
    "2015-07","2015-08","2015-09","2015-10","2015-11","2015-12",
    "2016-01","2016-02","2016-03","2016-04","2016-05","2016-06",
    "2016-07","2016-08","2016-09","2016-10","2016-11","2016-12",
    "2017-01","2017-02","2017-03","2017-04","2017-05","2017-06",
    "2017-07","2017-08","2017-09","2017-10","2017-11","2017-12",
    "2018-01","2018-02","2018-03","2018-04","2018-05","2018-06",
    "2018-07","2018-08","2018-09","2018-10","2018-11","2018-12",
    "2019-01","2019-02","2019-03","2019-04","2019-05","2019-06",
    "2019-07","2019-08","2019-09","2019-10","2019-11","2019-12",
    "2020-01","2020-02","2020-03","2020-04","2020-05","2020-06",
    "2020-07","2020-08","2020-09","2020-10","2020-11","2020-12",
    "2021-01","2021-02","2021-03","2021-04","2021-05","2021-06",
    "2021-07","2021-08","2021-09","2021-10","2021-11","2021-12",
    "2022-01","2022-02","2022-03","2022-04","2022-05","2022-06",
    "2022-07","2022-08","2022-09","2022-10","2022-11","2022-12",
    "2023-01","2023-02","2023-03","2023-04","2023-05","2023-06",
    "2023-07","2023-08","2023-09","2023-10","2023-11","2023-12",
    "2024-01","2024-02","2024-03","2024-04","2024-05","2024-06",
    "2024-07","2024-08","2024-09","2024-10","2024-11","2024-12"
  ),
  saron = c(
    2.28,1.342026,2.361749,2.547827,3.047974,3.054887,
    2.778948,3.125945,2.991287,2.967391,2.955805,3.490226,
    3.308556,3.282052,3.250111,3.085493,3.275508,3.283814,
    3.226346,3.123531,2.027698,2.118133,1.960142,1.469348,
    1.203506,1.571053,1.202675,1.418686,0.974746,0.937309,
    0.703175,0.603556,0.50856,0.517184,0.506908,0.362647,
    0.486557,0.562408,0.177559,0.094747,0.13474,0.14823,
    0.111008,0.053337,0.145845,0.113241,0.117566,0.126631,
    0.098549,0.100093,0.110365,0.108065,0.112946,0.360676,
    0.1953,0.173508,0.53447,0.63083,0.503354,0.497394,
    0.654176,0.67587,0.809343,0.646173,0.665846,0.631008,
    0.678098,0.677405,0.674366,0.673334,0.68404,0.609864,
    0.828563,0.895374,1.05294,1.187275,1.11309,1.242492,
    1.345125,1.370228,1.682963,1.627171,1.768215,1.897995,
    1.905279,1.835111,1.979335,2.066636,2.165807,2.418879,
    2.490651,2.3134,2.209981,2.118889,2.115592,1.873853,
    2.241335,2.240998,1.894609,1.850478,1.796851,1.860357,
    1.955679,1.933609,1.666335,0.522862,0.03909,0.019608,
    0.080879,0.035864,0.031394,0.03359,0.034996,0.020048,
    0.016977,0.018446,0.024256,0.045043,0.043573,0.031984,
    0.027068,0.037635,0.052509,0.027666,0.016089,0.059386,
    0.079548,0.318768,0.093595,0.058606,0.15866,0.050282,
    0.10152,0.078858,0.083753,0.030437,0.02816,0.07111,
    0.05025,-0.009758,0.008339,0.002873,0.02014,0.018136,
    -0.012948,-0.001064,0.007232,-0.017135,0.016374,0.027838,
    -0.057817,-0.023866,0.022813,-0.027541,0.04,0.032766,
    -0.028182,-0.035067,-0.017292,-0.008163,-0.024285,0.004224,
    -0.005746,0.010574,-0.001193,-0.016479,-0.033343,0.089315,
    -0.015391,-0.02602,-0.000316,-0.038873,-0.022355,-0.036625,
    -0.034751,0.006218,0.01231,-0.034484,-0.015032,0.003368,
    -0.678498,-0.7561,-0.730568,-0.722648,-0.726401,-0.727129,
    -0.738677,-0.724588,-0.719895,-0.724732,-0.72187,-0.721086,
    -0.723007,-0.733788,-0.737954,-0.726368,-0.729792,-0.765593,
    -0.745432,-0.731087,-0.744965,-0.729412,-0.728146,-0.731921,
    -0.732656,-0.72986,-0.737014,-0.738899,-0.734836,-0.734155,
    -0.732636,-0.732305,-0.742996,-0.737404,-0.736376,-0.746149,
    -0.740278,-0.759249,-0.73834,-0.729806,-0.728226,-0.730086,
    -0.730823,-0.731997,-0.785767,-0.73731,-0.732697,-0.730971,
    -0.731819,-0.738785,-0.737656,-0.73173,-0.73687,-0.74023,
    -0.74512,-0.74726,-0.74627,-0.73297,-0.7065,-0.65925,
    -0.70191,-0.70741,-0.66619,-0.65946,-0.65962,-0.66239,
    -0.7037,-0.70568,-0.71371,-0.71804,-0.72109,-0.726264,
    -0.725018,-0.725267,-0.72334,-0.725071,-0.725578,-0.722566,
    -0.721564,-0.72305,-0.672877,-0.693678,-0.680889,-0.68483,
    -0.696923,-0.698075,-0.701726,-0.701592,-0.692302,-0.195447,
    -0.18865,-0.200623,0.43653,0.470718,0.459251,0.942118,
    0.946142,0.937929,1.418617,1.419656,1.441883,1.706544,
    1.702332,1.705343,1.714893,1.704967,1.701526,1.695237,
    1.698236,1.697838,1.464207,1.444518,1.450122,1.215794,
    1.21096,1.217226,0.957401,0.949059,0.942743,0.451195
  )
)

# IPC mensuel → moyenne annuelle (BNS/OFS)
ipc_m <- tibble(
  date = saron_m$date,
  ipc = c(
    1.6,1.6,1.5,1.4,1.6,1.8,1.9,1.1,1.4,1.3,1.9,1.5,
    1.3,0.8,1,1.2,1.8,1.6,1.4,1.1,0.7,0.6,0.3,0.3,
    0.5,0.7,0.5,1.1,0.6,0.3,-0.1,0.5,0.5,1.2,0.9,0.9,
    0.8,0.9,1.3,0.7,0.4,0.5,0.3,0.5,0.5,0.5,0.5,0.6,
    0.2,0.1,-0.1,0.5,0.9,1.1,0.9,1,0.9,1.3,1.5,1.3,
    1.2,1.4,1.4,1.4,1.1,0.7,1.2,1,1.4,1.3,1,1,
    1.3,1.4,1,1.1,1.4,1.6,1.4,1.5,0.8,0.3,0.5,0.6,
    0.1,0,0.2,0.5,0.5,0.6,0.7,0.4,0.7,1.3,1.8,2,
    2.4,2.4,2.6,2.3,2.9,2.9,3.1,2.9,2.9,2.6,1.5,0.7,
    0.1,0.2,-0.4,-0.3,-1,-1,-1.2,-0.8,-0.9,-0.8,0,0.3,
    1,0.9,1.4,1.4,1.1,0.5,0.4,0.3,0.3,0.2,0.2,0.5,
    0.3,0.5,1,0.3,0.4,0.6,0.5,0.2,0.5,-0.1,-0.5,-0.7,
    -0.8,-0.9,-1,-1,-1,-1.1,-0.7,-0.5,-0.4,-0.2,-0.4,-0.4,
    -0.3,-0.3,-0.6,-0.6,-0.5,-0.1,0,0,-0.1,-0.3,0.1,0.1,
    0.1,-0.1,0,0,0.2,0,-0,-0.1,-0.1,0,-0.1,-0.3,
    -0.5,-0.8,-0.9,-1.1,-1.2,-1,-1.3,-1.4,-1.4,-1.4,-1.4,-1.3,
    -1.3,-0.8,-0.9,-0.4,-0.4,-0.4,-0.2,-0.1,-0.2,-0.2,-0.3,0,
    0.3,0.6,0.6,0.4,0.5,0.2,0.3,0.5,0.7,0.7,0.8,0.8,
    0.7,0.6,0.8,0.8,1,1.1,1.2,1.2,1,1.1,0.9,0.7,
    0.6,0.6,0.7,0.7,0.6,0.6,0.3,0.3,0.1,-0.3,-0.1,0.2,
    0.2,-0.1,-0.5,-1.1,-1.3,-1.3,-0.9,-0.9,-0.8,-0.6,-0.7,-0.8,
    -0.5,-0.5,-0.2,0.3,0.6,0.6,0.7,0.9,0.9,1.2,1.5,1.5,
    1.6,2.2,2.4,2.5,2.9,3.4,3.4,3.5,3.3,3,3,2.8,
    3.3,3.4,2.9,2.6,2.2,1.7,1.6,1.6,1.7,1.7,1.4,1.7,
    1.3,1.2,1,1.4,1.4,1.3,1.3,1.1,0.8,0.6,0.7,0.6
  )
)

# Agrégation annuelle
saron_a <- saron_m %>%
  mutate(annee = as.integer(substr(date, 1, 4))) %>%
  filter(annee >= 2007, annee <= 2024) %>%
  group_by(annee) %>%
  summarise(saron = mean(saron, na.rm = TRUE))

ipc_a <- ipc_m %>%
  mutate(annee = as.integer(substr(date, 1, 4))) %>%
  filter(annee >= 2007, annee <= 2024) %>%
  group_by(annee) %>%
  summarise(ipc = mean(ipc, na.rm = TRUE))

# Tableau consolidé
df <- fiscal %>%
  left_join(pib,     by = "annee") %>%
  left_join(saron_a, by = "annee") %>%
  left_join(ipc_a,   by = "annee")

cat("Tableau consolidé :", nrow(df), "observations,", ncol(df), "variables\n")
cat("Valeurs manquantes par colonne :\n")
print(colSums(is.na(df)))

# -----------------------------------------------------------------------------
# 3. STATISTIQUES DESCRIPTIVES — ON REGARDE LES DONNÉES
# -----------------------------------------------------------------------------
# Avant tout graphique, avant tout test : les chiffres bruts.
# On cherche : ordres de grandeur, tendances visibles, anomalies, ruptures.
# -----------------------------------------------------------------------------

cat("\n=== STATISTIQUES DESCRIPTIVES ===\n")

desc <- df %>%
  dplyr::select(annee, total, ir, ben_pm, fortune,
                enreg_timbre, successions, ifd, saron, ipc, pib_ge) %>%
  summary()
print(desc)

# Taux de croissance annuel moyen (TCAM) — séries fiscales principales
tcam <- function(x, n) (x[n] / x[1])^(1/(n-1)) - 1

cat("\nTCAM 2007–2024 :\n")
cat("  Total recettes :", round(tcam(df$total, 18) * 100, 2), "%\n")
cat("  IR             :", round(tcam(df$ir, 18) * 100, 2), "%\n")
cat("  Bénéfice PM    :", round(tcam(df$ben_pm, 18) * 100, 2), "%\n")
cat("  IFD            :", round(tcam(df$ifd, 18) * 100, 2), "%\n")

# Coefficient de variation (volatilité relative)
cv <- function(x) round(sd(x, na.rm = TRUE) / mean(x, na.rm = TRUE) * 100, 1)

cat("\nCoefficient de variation (%) — mesure de volatilité :\n")
cat("  Total recettes :", cv(df$total), "%\n")
cat("  IR             :", cv(df$ir), "%\n")
cat("  Bénéfice PM    :", cv(df$ben_pm), "%\n")
cat("  Fortune        :", cv(df$fortune), "%\n")
cat("  Enregistrement et timbre (OCSTAT):", cv(df$enreg_timbre), "%\n")
cat("  Successions    :", cv(df$successions), "%\n")
cat("  IFD            :", cv(df$ifd), "%\n")

# Variations annuelles — pour repérer les années atypiques
df <- df %>%
  arrange(annee) %>%
  mutate(
    var_total   = c(NA, diff(total)),
    var_total_p = c(NA, diff(total) / lag(total)[-1] * 100),
    var_ben_pm  = c(NA, diff(ben_pm)),
    var_ifd     = c(NA, diff(ifd))
  )

cat("\nVariations annuelles du total des recettes (M CHF) :\n")
print(df %>% dplyr::select(annee, total, var_total, var_total_p) %>%
        mutate(across(where(is.numeric), ~round(., 1))))

# -----------------------------------------------------------------------------
# 4. GRAPHIQUE 1 — ÉVOLUTION BRUTE DU TOTAL
# -----------------------------------------------------------------------------
# Premier regard : la série telle qu'elle est.
# On annote les années qui semblent atypiques.
# -----------------------------------------------------------------------------

couleurs <- c("#2C3E50", "#E74C3C", "#2980B9", "#27AE60", "#F39C12")

# Identifier les années avec variation > 10% ou < -5%
ruptures <- df %>%
  filter(abs(var_total_p) > 8 | annee %in% c(2009, 2010, 2020)) %>%
  filter(!is.na(var_total_p))

g1 <- ggplot(df, aes(x = annee, y = total)) +
  geom_line(color = couleurs[1], linewidth = 1.3) +
  geom_point(color = couleurs[1], size = 2.5) +
  # Annotations des années atypiques
  geom_point(data = ruptures,
             aes(y = total), color = couleurs[2],
             size = 4, shape = 21, fill = "white", stroke = 1.5) +
  geom_text(data = ruptures,
            aes(y = total,
                label = paste0(annee, "\n",
                               ifelse(var_total_p > 0, "+", ""),
                               round(var_total_p, 1), "%")),
            vjust = -1.2, size = 2.8, color = couleurs[2]) +
  scale_y_continuous(
    labels = label_number(scale = 1/1000, suffix = " Mrd CHF"),
    limits = c(5000, 11000)
  ) +
  scale_x_continuous(breaks = seq(2007, 2024, by = 2)) +
  labs(
    title    = "Recettes fiscales totales — Canton de Genève, 2007–2024",
    subtitle = "Les cercles rouges signalent les années avec une variation supérieure à 8%",
    x = NULL, y = NULL,
    caption  = "Source : OCSTAT, T18.02.1.15 | Unité : milliards de CHF"
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold"))

print(g1)

# -----------------------------------------------------------------------------
# 5. GRAPHIQUE 2 — DÉCOMPOSITION PAR COMPOSANTE
# -----------------------------------------------------------------------------
# On regarde chaque composante séparément pour comprendre
# ce qui tire le total vers le haut ou vers le bas.
# -----------------------------------------------------------------------------

df_long <- df %>%
  dplyr::select(annee, ir, ben_pm, fortune, ifd, enreg_timbre) %>%
  pivot_longer(-annee, names_to = "composante", values_to = "valeur") %>%
  mutate(composante = recode(composante,
                             "ir"        = "Impôt sur le revenu (PP)",
                             "ben_pm"    = "Impôt sur le bénéfice (PM)",
                             "fortune"   = "Impôt sur la fortune (PP)",
                             "ifd"       = "Part cantonale IFD",
                             "enreg_timbre"= "Enregistrement et timbre (OCSTAT)n"
  ))

g2 <- ggplot(df_long, aes(x = annee, y = valeur, color = composante)) +
  geom_line(linewidth = 1.1) +
  geom_point(size = 1.8) +
  scale_color_manual(values = couleurs) +
  scale_y_continuous(labels = label_number(suffix = " M")) +
  scale_x_continuous(breaks = seq(2007, 2024, by = 2)) +
  labs(
    title    = "Décomposition des recettes fiscales par composante",
    subtitle = "Cinq composantes principales — Canton de Genève, 2007–2024",
    x = NULL, y = "Millions CHF",
    color    = NULL,
    caption  = "Source : OCSTAT, T18.02.1.15"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "bottom",
    legend.text     = element_text(size = 9)
  ) +
  guides(color = guide_legend(nrow = 2))

print(g2)

# -----------------------------------------------------------------------------
# 6. GRAPHIQUE 3 — VARIABLES MACRO
# -----------------------------------------------------------------------------

g3_saron <- ggplot(df, aes(x = annee, y = saron)) +
  geom_line(color = couleurs[2], linewidth = 1.1) +
  geom_point(color = couleurs[2], size = 2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  annotate("text", x = 2016, y = -0.5,
           label = "Taux négatifs\n2015–2022",
           size = 3, color = "grey40") +
  scale_x_continuous(breaks = seq(2007, 2024, by = 2)) +
  labs(title = "Taux SARON — moyenne annuelle",
       x = NULL, y = "%",
       caption = "Source : BNS, data.snb.ch") +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold", size = 10))

g3_ipc <- ggplot(df, aes(x = annee, y = ipc)) +
  geom_line(color = couleurs[3], linewidth = 1.1) +
  geom_point(color = couleurs[3], size = 2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  scale_x_continuous(breaks = seq(2007, 2024, by = 2)) +
  labs(title = "Inflation IPC — moyenne annuelle",
       x = NULL, y = "%",
       caption = "Source : OFS via BNS, data.snb.ch") +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold", size = 10))

g3_pib <- ggplot(df %>% filter(!is.na(pib_ge)),
                 aes(x = annee, y = pib_ge)) +
  geom_line(color = couleurs[4], linewidth = 1.1) +
  geom_point(color = couleurs[4], size = 2) +
  scale_y_continuous(labels = label_number(scale = 1/1000,
                                           suffix = " Mrd")) +
  scale_x_continuous(breaks = seq(2008, 2022, by = 2)) +
  labs(title = "PIB nominal — Canton de Genève",
       subtitle = "2008–2022 (2022 = provisoire)",
       x = NULL, y = "Milliards CHF",
       caption = "Source : OFS, Comptes régionaux") +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold", size = 10))

(g3_saron + g3_ipc) / g3_pib +
  plot_annotation(
    title = "Variables macroéconomiques — Suisse et Genève",
    theme = theme(plot.title = element_text(face = "bold"))
  )

# -----------------------------------------------------------------------------
# 7. GRAPHIQUE 4 — CORRÉLATIONS VISUELLES
# -----------------------------------------------------------------------------
# Avant tout test de corrélation : regarder les nuages de points.
# On cherche des relations visuelles entre les recettes et les variables macro.
# -----------------------------------------------------------------------------

df_corr <- df %>% filter(!is.na(pib_ge))

g4a <- ggplot(df_corr, aes(x = pib_ge/1000, y = total/1000)) +
  geom_point(color = couleurs[1], size = 3) +
  geom_smooth(method = "lm", se = TRUE,
              color = couleurs[2], fill = couleurs[2], alpha = 0.15) +
  geom_text(aes(label = annee), vjust = -0.8, size = 2.5, color = "grey40") +
  labs(title = "Total recettes vs PIB",
       x = "PIB (Mrd CHF)", y = "Recettes (Mrd CHF)") +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold", size = 10))

g4b <- ggplot(df, aes(x = saron, y = total/1000)) +
  geom_point(color = couleurs[1], size = 3) +
  geom_smooth(method = "lm", se = TRUE,
              color = couleurs[3], fill = couleurs[3], alpha = 0.15) +
  geom_text(aes(label = annee), vjust = -0.8, size = 2.5, color = "grey40") +
  labs(title = "Total recettes vs SARON",
       x = "SARON (%)", y = "Recettes (Mrd CHF)") +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold", size = 10))

g4c <- ggplot(df, aes(x = ipc, y = total/1000)) +
  geom_point(color = couleurs[1], size = 3) +
  geom_smooth(method = "lm", se = TRUE,
              color = couleurs[4], fill = couleurs[4], alpha = 0.15) +
  geom_text(aes(label = annee), vjust = -0.8, size = 2.5, color = "grey40") +
  labs(title = "Total recettes vs IPC",
       x = "IPC (%)", y = "Recettes (Mrd CHF)") +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold", size = 10))

g4d <- ggplot(df, aes(x = enreg_timbre, y = ben_pm)) +
  geom_point(color = couleurs[1], size = 3) +
  geom_smooth(method = "lm", se = TRUE,
              color = couleurs[5], fill = couleurs[5], alpha = 0.15) +
  geom_text(aes(label = annee), vjust = -0.8, size = 2.5, color = "grey40") +
  labs(title = "Bénéfice PM vs Enregistrement et timbre (OCSTAT)",
       x = "Enregistrement et timbre (OCSTAT) (M CHF)",
       y = "Bénéfice PM (M CHF)") +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold", size = 10))

(g4a + g4b) / (g4c + g4d) +
  plot_annotation(
    title    = "Relations entre recettes fiscales et variables macro",
    subtitle = "Nuages de points avec droite de régression — 2007–2024",
    caption  = "Note : 2022–2024 sont des années atypiques (RFFA) — à interpréter avec prudence",
    theme    = theme(plot.title = element_text(face = "bold"))
  )

# -----------------------------------------------------------------------------
# 8. MATRICE DE CORRÉLATION NUMÉRIQUE
# -----------------------------------------------------------------------------

cat("\n=== MATRICE DE CORRÉLATION ===\n")
cat("(sur la fenêtre commune 2008–2022 avec PIB)\n\n")

df_corr_mat <- df %>%
  filter(!is.na(pib_ge)) %>%
  dplyr::select(total, ir, ben_pm, fortune, ifd,
                enreg_timbre, pib_ge, saron, ipc) %>%
  cor(use = "complete.obs") %>%
  round(2)

print(df_corr_mat)

# -----------------------------------------------------------------------------
# 9. IDENTIFICATION DES ANOMALIES ET RUPTURES VISIBLES
# -----------------------------------------------------------------------------

cat("\n=== ANOMALIES ET POINTS ATYPIQUES ===\n\n")

cat("Successions 2009 :", df$successions[df$annee == 2009],
    "M — outlier majeur (médiane :", round(median(df$successions), 0), "M)\n")

cat("Variation totale 2022 :",
    round(df$var_total_p[df$annee == 2022], 1),
    "% — plus forte hausse de la série\n")

cat("Variation totale 2010 :",
    round(df$var_total_p[df$annee == 2010], 1),
    "% — plus forte baisse de la série\n")

cat("IFD 2023 :", df$ifd[df$annee == 2023],
    "M — niveau exceptionnel (médiane :",
    round(median(df$ifd), 0), "M)\n")

cat("Bénéfice PM 2023 :", df$ben_pm[df$annee == 2023],
    "M — niveau exceptionnel (médiane :",
    round(median(df$ben_pm), 0), "M)\n")

# Sauvegarde des graphiques
ggsave("01_total_evolution.png",     g1,    width = 12, height = 6, dpi = 150)
ggsave("01_decomposition.png",       g2,    width = 12, height = 6, dpi = 150)

cat("\n✓ Graphiques sauvegardés\n")

# =============================================================================
# DÉCISION FINALE — CE QUE LES DONNÉES NOUS POSENT COMME QUESTIONS
# =============================================================================
# Cette section est le cœur de l'approche inductive.
# Les questions ici déterminent exactement ce que le script 02 devra faire.
# =============================================================================

cat("\n")
cat("=============================================================\n")
cat("QUESTIONS POSÉES PAR LES DONNÉES — À TRAITER DANS LE SCRIPT 02\n")
cat("=============================================================\n\n")

cat("Q1 — STATIONNARITÉ\n")
cat("    Les séries ont une tendance de fond visible et des ruptures en 2010\n")
cat("    et 2022. Sont-elles stationnaires ? De quel ordre d'intégration ?\n")
cat("    → Tests ADF et Phillips-Perron sur chaque série principale\n\n")

cat("Q2 — RUPTURES STRUCTURELLES\n")
cat("    2009 (successions), 2010 (baisse post-crise), 2020 (COVID),\n")
cat("    2022-2023 (RFFA) sont des années visuellement atypiques.\n")
cat("    Ces ruptures sont-elles statistiquement confirmées ?\n")
cat("    → Test de Chow sur 2009, 2020 et 2022\n\n")

cat("Q3 — OUTLIER SUCCESSIONS 2009\n")
cat("    308M en 2009 contre une médiane de ~190M.\n")
cat("    Comment traiter cet outlier dans les modèles ?\n")
cat("    → Dummy variable ou exclusion à documenter\n\n")

cat("Q4 — COINTÉGRATION\n")
cat("    Si total, ben_pm et ifd sont I(1), sont-ils cointégrés ?\n")
cat("    La réponse détermine VAR en différences vs VECM.\n")
cat("    → Test de Johansen sur la fenêtre commune disponible\n\n")

cat("Q5 — RELATIONS AVEC LES VARIABLES MACRO\n")
cat("    La matrice de corrélation montre des corrélations élevées\n")
cat("    mais potentiellement spurieuses (séries non stationnaires).\n")
cat("    → À traiter après les tests de stationnarité\n\n")

cat("Q6 — TRAITEMENT DE LA RFFA\n")
cat("    La hausse 2022-2023 est partiellement attribuable à la RFFA.\n")
cat("    Faut-il une dummy variable ? À partir de quelle année ?\n")
cat("    → Dummy RFFA = 1 à partir de 2022, testée formellement\n\n")

cat("→ Le script 02 répondra à ces 6 questions dans cet ordre.\n")
cat("→ Les réponses détermineront les modèles du script 03.\n")