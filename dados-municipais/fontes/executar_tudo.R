# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: executar_tudo.R
# OBJETIVO: Rodar o pipeline completo: dicionario de municipios, extracao (01) e
#           tratamento (02) de cada fonte e, por fim, a consolidacao do painel.
#           Falhas em uma fonte nao interrompem as demais; o resumo sai no fim.
# COMO EXECUTAR: Rscript fontes/executar_tudo.R [fonte1 fonte2 ...]
#   Sem argumentos, roda todas as fontes. Variaveis uteis para testes:
#   PAINEL_UFS="MG,ES"  PAINEL_ANO_INICIAL=2020  PAINEL_REBAIXAR=TRUE
# ------------------------------------------------------------------------------

.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(.dir, "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()

rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
rodar <- function(script) {
  log_msg("==> ", script)
  inicio <- Sys.time()
  status <- system2(rscript, shQuote(script), stdout = "", stderr = "")
  data.frame(script = script, status = if (identical(status, 0L)) "OK" else paste("ERRO", status),
             minutos = round(as.numeric(difftime(Sys.time(), inicio, units = "mins")), 1))
}

pastas <- list.dirs(DIR_FONTES, recursive = FALSE, full.names = TRUE)
pastas <- pastas[!basename(pastas) %in% c("00_comum")]
selecionadas <- commandArgs(trailingOnly = TRUE)
if (length(selecionadas)) pastas <- pastas[basename(pastas) %in% selecionadas]

resultados <- list(rodar(file.path(DIR_FONTES, "00_comum", "01_dicionario_municipios.R")))
for (pasta in pastas) {
  scripts <- list.files(pasta, pattern = "^0[12]_.*[.]R$", full.names = TRUE)
  for (s in sort(scripts)) resultados[[length(resultados) + 1L]] <- rodar(s)
}
resultados[[length(resultados) + 1L]] <- rodar(file.path(DIR_FONTES, "00_comum", "consolidar_painel.R"))
resumo <- do.call(rbind, resultados)
print(resumo, row.names = FALSE)
escrever_csv(resumo, file.path(DIR_LOGS, paste0("resumo_execucao_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")))
