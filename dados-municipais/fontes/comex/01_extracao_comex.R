# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_comex.R
# FONTE: SECEX/MDIC - Comex Stat, exportacoes e importacoes por municipio
# OBJETIVO: Baixar e preservar os arquivos anuais EXP_<ANO>_MUN.csv e
#           IMP_<ANO>_MUN.csv (municipio-mes-SH4-pais), sem transformar.
# COBERTURA: Brasil, todos os municipios; 2000 ate o ano corrente
# PERIODICIDADE: mensal (um arquivo por ano; o ano corrente e revisado todo mes)
# ENDPOINT: https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/{EXP|IMP}_<ANO>_MUN.csv
# SAIDAS: dados/brutos/comex/EXP_<ANO>_MUN.csv e IMP_<ANO>_MUN.csv
# COMO EXECUTAR: Rscript fontes/comex/01_extracao_comex.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "comex"

ANO_INICIAL <- ano_inicial_efetivo(2000L)
MES_ATUAL <- as.integer(format(Sys.Date(), "%m"))
URL_BASE <- "https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/"
COLUNAS_OBRIGATORIAS <- c("CO_ANO", "CO_MES", "SH4", "CO_PAIS", "SG_UF_MUN",
                          "CO_MUN", "KG_LIQUIDO", "VL_FOB")
dir_saida <- dir_brutos(FONTE)

# 1. Plano de coleta: um arquivo por fluxo (EXP/IMP) e ano.
plano <- expand.grid(fluxo = c("EXP", "IMP"), ano = seq(ANO_INICIAL, ANO_ATUAL),
                     stringsAsFactors = FALSE)
plano$arquivo <- sprintf("%s_%d_MUN.csv", plano$fluxo, plano$ano)
plano$url <- paste0(URL_BASE, plano$arquivo)
plano$destino <- file.path(dir_saida, plano$arquivo)

# Validador: tamanho minimo e cabecalho oficial (campos entre aspas, separador ;).
validar_csv_comex <- function(arquivo) {
  if (file.info(arquivo)$size < 1000) return(FALSE)
  cabecalho <- readLines(arquivo, n = 1L, warn = FALSE, encoding = "UTF-8")
  campos <- gsub('"', "", trimws(strsplit(sub("^\ufeff", "", cabecalho), ";", fixed = TRUE)[[1L]]))
  all(COLUNAS_OBRIGATORIAS %in% campos)
}

# 2. Download atomico com reutilizacao. Anos encerrados nao mudam; o ano
#    corrente e sempre rebaixado (a fonte revisa os meses ja publicados) e o
#    ano anterior tambem e rebaixado no primeiro trimestre, periodo em que a
#    fonte ainda consolida seus ultimos meses.
n_ok <- 0L
for (i in seq_len(nrow(plano))) {
  ano <- plano$ano[i]
  encerrado <- ano < ANO_ATUAL - 1L || (ano == ANO_ATUAL - 1L && MES_ATUAL > 3L)
  resultado <- tryCatch(
    baixar_arquivo(plano$url[i], plano$destino[i], reutilizar = REUTILIZAR_BRUTOS && encerrado,
                   validador = validar_csv_comex),
    error = function(e) e
  )
  if (inherits(resultado, "error")) {
    # O arquivo do ano corrente so passa a existir apos a primeira divulgacao
    # mensal do ano; sua ausencia nao e erro.
    if (ano == ANO_ATUAL) {
      log_msg("Aviso: ", plano$arquivo[i], " indisponivel: ", conditionMessage(resultado))
      next
    }
    stop(resultado)
  }
  n_ok <- n_ok + 1L
}

registrar_execucao(FONTE, "extracao", paste0(n_ok, " de ", nrow(plano), " arquivos em ", dir_saida))
