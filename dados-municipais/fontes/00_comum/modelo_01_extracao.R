# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_<fonte>.R   (MODELO - copie e adapte)
# FONTE: <orgao> - <conjunto de dados>
# OBJETIVO: Baixar e preservar os arquivos brutos, sem transformar.
# COBERTURA: Brasil, todos os municipios; <ano inicial> ate o mais recente.
# PERIODICIDADE: anual | mensal
# ENDPOINT: <url>
# SAIDAS: dados/brutos/<fonte>/...
# COMO EXECUTAR: Rscript fontes/<fonte>/01_extracao_<fonte>.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "<fonte>"

ANO_INICIAL <- ano_inicial_efetivo(2000L)
dir_saida <- dir_brutos(FONTE)

# 1. Plano de coleta: um item por arquivo/ano (descoberto no portal ou fixo)
plano <- data.frame(
  ano = seq(ANO_INICIAL, ANO_ATUAL),
  url = sprintf("https://exemplo.gov.br/arquivo_%d.csv", seq(ANO_INICIAL, ANO_ATUAL)),
  stringsAsFactors = FALSE
)
plano$destino <- file.path(dir_saida, basename(plano$url))

# 2. Download atomico com reutilizacao (arquivos de anos encerrados nao mudam;
#    o ano corrente e sempre rebaixado).
for (i in seq_len(nrow(plano))) {
  reutilizar <- REUTILIZAR_BRUTOS && plano$ano[i] < ANO_ATUAL
  baixar_arquivo(plano$url[i], plano$destino[i], reutilizar = reutilizar,
                 validador = function(f) file.info(f)$size > 1000)
}

registrar_execucao(FONTE, "extracao", paste0(nrow(plano), " arquivos em ", dir_saida))
