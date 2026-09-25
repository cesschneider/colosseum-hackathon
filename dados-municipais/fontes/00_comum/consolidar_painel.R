# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: consolidar_painel.R
# OBJETIVO: Reunir todas as bases tratadas (dados/tratados/<fonte>/*_municipal.csv)
#           em um painel unico no formato longo, mais o catalogo de variaveis com
#           a cobertura observada. E a camada que a aplicacao consome.
# SAIDAS: dados/painel/painel_municipal_long.csv
#             (fonte, variavel, codigo_municipio, ano, mes, valor)
#         dados/painel/painel_municipal_long.parquet (se o pacote arrow existir)
#         dados/painel/catalogo_variaveis.csv
#             (dicionarios das fontes + n_municipios, ano_min, ano_max, n_valores)
# COMO EXECUTAR: Rscript fontes/00_comum/consolidar_painel.R
# ------------------------------------------------------------------------------

.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(.dir, "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente("data.table")
library(data.table)

arquivos <- list.files(DIR_TRATADOS, pattern = "_municipal[.]csv$", recursive = TRUE, full.names = TRUE)
if (!length(arquivos)) stop("Nenhuma base tratada encontrada em ", DIR_TRATADOS)

longos <- lapply(arquivos, function(arquivo) {
  fonte <- basename(dirname(arquivo))
  log_msg("Lendo ", fonte, ": ", basename(arquivo))
  base <- as.data.table(ler_csv(arquivo))
  base[, codigo_municipio := sprintf("%07d", as.integer(codigo_municipio))]
  if (!"mes" %in% names(base)) base[, mes := NA_integer_]
  ids <- c("codigo_municipio", "ano", "mes")
  medidas <- setdiff(names(base), c(ids, "nome_municipio", "uf"))
  numericas <- medidas[vapply(medidas, function(v) is.numeric(base[[v]]) || is.logical(base[[v]]), logical(1))]
  if (!length(numericas)) return(NULL)
  longo <- melt(base[, c(ids, numericas), with = FALSE], id.vars = ids,
                variable.name = "variavel", value.name = "valor", variable.factor = FALSE)
  longo[, valor := as.numeric(valor)]
  longo <- longo[!is.na(valor)]
  longo[, fonte := fonte]
  longo[, tabela := sub("_municipal$", "", sub("[.]csv$", "", basename(arquivo)))]
  setcolorder(longo, c("fonte", "tabela", "variavel", "codigo_municipio", "ano", "mes", "valor"))
  longo
})
painel <- rbindlist(longos, use.names = TRUE)
setorder(painel, fonte, variavel, codigo_municipio, ano, mes)

dir.create(DIR_PAINEL, recursive = TRUE, showWarnings = FALSE)
destino_csv <- file.path(DIR_PAINEL, "painel_municipal_long.csv")
escrever_csv(painel, destino_csv)
log_msg("Painel longo: ", nrow(painel), " valores, ", uniqueN(painel$variavel), " variaveis, ",
        uniqueN(painel$codigo_municipio), " municipios -> ", destino_csv)
if (requireNamespace("arrow", quietly = TRUE)) {
  arrow::write_parquet(painel, file.path(DIR_PAINEL, "painel_municipal_long.parquet"))
  log_msg("Parquet gravado.")
}

# Catalogo: dicionarios declarados pelas fontes + cobertura observada.
dicionarios <- list.files(DIR_TRATADOS, pattern = "_dicionario_variaveis[.]csv$", recursive = TRUE, full.names = TRUE)
catalogo <- rbindlist(lapply(dicionarios, function(a) as.data.table(ler_csv(a))), use.names = TRUE, fill = TRUE)
cobertura <- painel[, .(n_municipios = uniqueN(codigo_municipio), ano_min = min(ano), ano_max = max(ano),
                        n_valores = .N, mensal = any(!is.na(mes))), by = .(fonte, tabela, variavel)]
if (nrow(catalogo)) {
  # A juncao e por (fonte, tabela, variavel): uma fonte pode ter a mesma variavel
  # em duas bases (ex.: mensal e anual). `tabela` e normalizada dos dois lados
  # (sem sufixo _municipal/.csv); quando o dicionario nao a informa, assume a
  # base padrao da fonte (<fonte>_municipal.csv, ou seja, tabela = fonte).
  normalizar_tabela <- function(x) sub("_municipal$", "", sub("[.]csv$", "", as.character(x)))
  catalogo[, fonte := as.character(fonte)]
  if (!"tabela" %in% names(catalogo)) catalogo[, tabela := NA_character_]
  catalogo[, tabela := normalizar_tabela(tabela)]
  catalogo[is.na(tabela) | tabela == "", tabela := fonte]
  catalogo <- merge(catalogo, cobertura, by = c("fonte", "tabela", "variavel"), all = TRUE)
} else {
  catalogo <- cobertura
}
setorder(catalogo, fonte, variavel)
escrever_csv(catalogo, file.path(DIR_PAINEL, "catalogo_variaveis.csv"))
sem_dicionario <- catalogo[is.na(descricao) | descricao == "", unique(paste(fonte, variavel, sep = ":"))]
if (length(sem_dicionario)) log_msg("Aviso: variaveis sem descricao no dicionario: ", paste(head(sem_dicionario, 20), collapse = ", "))
registrar_execucao("painel", "consolidacao", paste0(nrow(painel), " valores; ", nrow(catalogo), " variaveis"))
