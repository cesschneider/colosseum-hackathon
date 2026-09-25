# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_caged.R
# FONTE: MTE - Novo Caged (admissoes e desligamentos de empregados celetistas),
#        distribuido pela API OData do Ipeadata
# OBJETIVO: Baixar e preservar as series municipais mensais ADMISNC e DESLIGNC
#           exatamente como a API devolve (todos os niveis), sem transformar.
# COBERTURA: Brasil, todos os municipios; 2020-01 ate a ultima competencia
#            divulgada. O Ipeadata NAO possui series municipais do Caged antigo
#            (2004-2019): as series CAGED12_* existem apenas no nivel Brasil
#            (base "Macroeconomico"); na base "Regional" so ha ADMISNC/DESLIGNC.
# PERIODICIDADE: mensal; a API entrega um snapshot integral e pode revisar
#            retroativamente competencias ja divulgadas
# ENDPOINT: https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='<serie>')
# SAIDAS: dados/brutos/caged/ipeadata_<serie>.csv
#         dados/brutos/caged/ipeadata_<serie>_metadados.csv
# COMO EXECUTAR: Rscript fontes/caged/01_extracao_caged.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "caged"

# Series do Ipeadata (nivel "Municipios", "Novo Caged sem ajuste"):
#   ADMISNC  - empregados admitidos no mes
#   DESLIGNC - empregados desligados no mes (contagem positiva na API)
# O saldo (admitidos - desligados) e calculado apenas na etapa 02.
SERIES <- c("ADMISNC", "DESLIGNC")
dir_saida <- dir_brutos(FONTE)

baixar_serie_ipeadata <- function(serie, dir_saida) {
  # A API devolve a serie integral em URL fixa e pode revisar retroativamente
  # competencias ja divulgadas (declaracoes fora do prazo). Por isso o
  # snapshot e rebaixado a cada execucao; so e reutilizado quando ja foi
  # baixado hoje e PAINEL_REBAIXAR nao esta definida.
  destino <- file.path(dir_saida, paste0("ipeadata_", serie, ".csv"))
  baixado_hoje <- file.exists(destino) &&
    format(file.mtime(destino), "%Y-%m-%d") == format(Sys.time(), "%Y-%m-%d")
  if (REUTILIZAR_BRUTOS && baixado_hoje) {
    log_msg("Reutilizado (baixado hoje): ", basename(destino))
    return(invisible(destino))
  }
  log_msg("Baixando a serie ", serie, " do Ipeadata (serie integral, todos os niveis) ...")
  bruto <- ipeadata_valores(serie, timeout = TIMEOUT_PADRAO)
  colunas <- c("SERCODIGO", "VALDATA", "VALVALOR", "NIVNOME", "TERCODIGO")
  faltando <- setdiff(colunas, names(bruto))
  if (length(faltando)) stop("Schema inesperado na serie ", serie, ": faltam ", paste(faltando, collapse = ", "))
  municipal <- remover_acentos(as.character(bruto$NIVNOME)) %in% c("Municipios", "Municipio")
  if (!any(municipal)) stop("A serie ", serie, " nao possui registros no nivel municipal.")
  escrever_csv(bruto[colunas], destino)
  # Metadados da serie (nome, periodicidade, unidade, data de atualizacao na
  # API): documentam qual versao da serie foi preservada.
  meta <- ipeadata_metadados(serie)
  campos <- intersect(c("SERCODIGO", "SERNOME", "PERNOME", "UNINOME", "BASNOME", "FNTSIGLA",
                        "SERATUALIZACAO", "SERCOMENTARIO"), names(meta))
  escrever_csv(meta[campos], sub("[.]csv$", "_metadados.csv", destino))
  competencias <- substr(as.character(bruto$VALDATA[municipal]), 1L, 7L)
  log_msg(serie, ": ", nrow(bruto), " linhas (", sum(municipal), " municipais), competencias ",
          min(competencias), " a ", max(competencias), " -> ", basename(destino))
  invisible(destino)
}

for (serie in SERIES) baixar_serie_ipeadata(serie, dir_saida)

registrar_execucao(FONTE, "extracao", paste0(length(SERIES), " series em ", dir_saida))
