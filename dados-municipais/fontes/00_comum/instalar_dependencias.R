# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: instalar_dependencias.R
# OBJETIVO: Instalar (uma unica vez) os pacotes usados pelas fontes. Os scripts
#           de fonte nunca instalam pacotes sozinhos; eles apenas verificam.
# COMO EXECUTAR: Rscript fontes/00_comum/instalar_dependencias.R [--opcionais]
# ------------------------------------------------------------------------------

obrigatorios <- c("jsonlite", "curl", "data.table", "readxl", "openxlsx", "zip", "xml2", "stringi")
# Opcionais: exigidos apenas por fontes especificas.
#   microdatasus + read.dbc : SIM (microdados de obitos)
#   geobr + sf              : 02_vizinhos_municipios.R
#   arrow                   : exportacao do painel em Parquet
opcionais <- c("microdatasus", "read.dbc", "geobr", "sf", "arrow")

instalar <- function(pacotes) {
  faltantes <- pacotes[!vapply(pacotes, requireNamespace, logical(1), quietly = TRUE)]
  if (!length(faltantes)) { message("Todos instalados: ", paste(pacotes, collapse = ", ")); return(invisible()) }
  message("Instalando: ", paste(faltantes, collapse = ", "))
  utils::install.packages(faltantes, repos = "https://cloud.r-project.org", dependencies = TRUE)
}

instalar(obrigatorios)
if ("--opcionais" %in% commandArgs(trailingOnly = TRUE)) instalar(opcionais)
