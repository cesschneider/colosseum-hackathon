# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_ibge_populacao.R
# FONTE: IBGE - populacao residente estimada (1o de julho) e populacao residente
#        total (Censos/Contagem), distribuidas pela API OData do Ipeadata
# OBJETIVO: Baixar e preservar as series ESTIMA_PO e POPTOT exatamente como a
#           API devolve (todos os niveis territoriais), sem transformar.
# COBERTURA: Brasil, todos os municipios; serie historica integral do Ipeadata
#            (ESTIMA_PO desde 1992; POPTOT nos anos censitarios)
# PERIODICIDADE: anual (ESTIMA_PO); decenal/censitaria (POPTOT)
# ENDPOINT: https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='<serie>')
# SAIDAS: dados/brutos/ibge_populacao/ipeadata_<serie>.csv
#         dados/brutos/ibge_populacao/ipeadata_<serie>_metadados.csv
# COMO EXECUTAR: Rscript fontes/ibge_populacao/01_extracao_ibge_populacao.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "ibge_populacao"

# Series do Ipeadata (nivel "Municipios"):
#   ESTIMA_PO - populacao residente estimada em 1o de julho (IBGE, anual)
#   POPTOT    - populacao residente total dos Censos e da Contagem 2007 (IBGE)
SERIES <- c("ESTIMA_PO", "POPTOT")
dir_saida <- dir_brutos(FONTE)

baixar_serie_ipeadata <- function(serie, dir_saida) {
  # A API devolve a serie integral em URL fixa e pode revisar retroativamente
  # valores ja divulgados (novas estimativas, revisoes do IBGE). Por isso o
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
  anos <- substr(as.character(bruto$VALDATA[municipal]), 1L, 4L)
  log_msg(serie, ": ", nrow(bruto), " linhas (", sum(municipal), " municipais), anos ",
          min(anos), " a ", max(anos), " -> ", basename(destino))
  invisible(destino)
}

for (serie in SERIES) baixar_serie_ipeadata(serie, dir_saida)

registrar_execucao(FONTE, "extracao", paste0(length(SERIES), " series em ", dir_saida))
