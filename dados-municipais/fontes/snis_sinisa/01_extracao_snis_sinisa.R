# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_snis_sinisa.R
# FONTE: Ministerio das Cidades - SNIS (serie historica 2000-2022) e SINISA
#        (ano de referencia 2023 em diante): agua, esgoto e qualidade dos servicos
# OBJETIVO: Baixar e preservar os pacotes oficiais do SINISA (planilhas da Base
#           Municipal de agua e de esgoto) e conferir a presenca das exportacoes
#           manuais da Serie Historica do SNIS (ver README).
# COBERTURA: Brasil, todos os municipios; 2000 ate o ultimo ano divulgado.
# PERIODICIDADE: anual
# ENDPOINT: https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/resultados-sinisa
#           https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/planilhas-de-informacoes-e-indicadores
#           https://app4.cidades.gov.br/serieHistorica/ (exportacao manual)
# SAIDAS: dados/brutos/snis_sinisa/sinisa/<pacote>.zip e
#         dados/brutos/snis_sinisa/sinisa/<ano>/*_Base Municipal_*.xlsx
#         dados/brutos/snis_sinisa/serie_historica/ (exportacoes manuais, conferidas)
# COMO EXECUTAR: Rscript fontes/snis_sinisa/01_extracao_snis_sinisa.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "snis_sinisa"

URL_BASE       <- "https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/"
URL_RESULTADOS <- paste0(URL_BASE, "resultados-sinisa")
URL_PLANILHAS  <- paste0(URL_BASE, "planilhas-de-informacoes-e-indicadores")
# Pacotes conhecidos do ano de referencia 2023 (reserva se a descoberta falhar):
# agua = SINISA_Resultados_Ref2023.zip; esgoto = SINISA_ESGOTO_Planilhas_2023_v2.zip.
URLS_CONHECIDAS <- c(
  paste0(URL_BASE, "arquivos/SINISA_Resultados_Ref2023.zip"),
  paste0(URL_BASE, "resultados-sinisa/SINISA_ESGOTO_Planilhas_2023_v2.zip")
)
PADRAO_ZIP <- "SINISA_[A-Za-z_]*(Resultados_Ref|Planilhas_)[0-9]{4}[^/]*[.]zip$"
PADRAO_BASE_MUNICIPAL <- "Informacoes_Gestao ?Tecnica ?(Agua|Esgoto)_Base ?Municipal"

e_zip <- function(arquivo) {
  if (file.info(arquivo)$size < 1e6) return(FALSE)
  con <- file(arquivo, "rb")
  on.exit(close(con), add = TRUE)
  identical(readBin(con, "raw", 2L), as.raw(c(0x50, 0x4B)))
}

# 1. Descoberta dos pacotes ZIP do SINISA nas paginas oficiais. Anos novos com o
#    mesmo padrao de nome entram automaticamente; as URLs conhecidas garantem o
#    ano 2023 mesmo se a pagina mudar. O servidor recusa HEAD (403): so GET.
descobrir_zips <- function(url) {
  tryCatch(listar_links_pagina(url, padrao = PADRAO_ZIP), error = function(e) {
    log_msg("Aviso: nao foi possivel ler ", url, ": ", conditionMessage(e))
    character()
  })
}
links <- unique(c(unlist(lapply(c(URL_RESULTADOS, URL_PLANILHAS), descobrir_zips)), URLS_CONHECIDAS))
links <- ifelse(grepl("^https?://", links), links, paste0("https://www.gov.br", links))
plano <- data.frame(
  url = links,
  ano = as.integer(sub(".*(Ref|_)([0-9]{4}).*", "\\2", basename(links))),
  destino = file.path(dir_brutos(FONTE, "sinisa"), basename(links)),
  stringsAsFactors = FALSE
)
plano <- plano[!duplicated(plano$destino), ]
log_msg(nrow(plano), " pacote(s) SINISA: ", paste(basename(plano$url), collapse = ", "))

# 2. Download (cerca de 30 MB para 2023; o servidor e lento) e extracao apenas
#    das planilhas "Informacoes de Gestao Tecnica - Base Municipal" de agua e
#    esgoto. Planilhas de prestadores locais/regionais replicam a base municipal
#    e nao sao extraidas (evita dupla contagem).
for (i in seq_len(nrow(plano))) {
  baixar_arquivo(plano$url[i], plano$destino[i], tamanho_minimo = 1e6, validador = e_zip)
  membros <- listar_membros_zip(plano$destino[i])
  membros <- membros[grepl(PADRAO_BASE_MUNICIPAL, membros, ignore.case = TRUE) & grepl("[.]xlsx$", membros)]
  if (!length(membros)) {
    log_msg("Aviso: nenhuma planilha da Base Municipal em ", basename(plano$destino[i]))
    next
  }
  dir_ano <- dir_brutos(FONTE, "sinisa", plano$ano[i])
  pendentes <- membros[!file.exists(file.path(dir_ano, basename(membros)))]
  if (!REUTILIZAR_BRUTOS) pendentes <- membros
  if (!length(pendentes)) {
    log_msg("Planilhas ja extraidas em ", dir_ano)
    next
  }
  temporario <- tempfile("sinisa_")
  descompactar_zip(plano$destino[i], temporario, membros = pendentes)
  extraidos <- list.files(temporario, pattern = "[.]xlsx$", recursive = TRUE, full.names = TRUE)
  file.copy(extraidos, file.path(dir_ano, basename(extraidos)), overwrite = TRUE)
  unlink(temporario, recursive = TRUE, force = TRUE)
  log_msg("Extraido(s) ", length(extraidos), " arquivo(s) para ", dir_ano)
}

# 3. Serie historica do SNIS (2000-2022): a aplicacao Serie Historica nao possui
#    download em massa documentado (a exportacao e um POST interno com ids de
#    glossario). As exportacoes manuais "Consolidado por Municipio" devem ser
#    salvas em dados/brutos/snis_sinisa/serie_historica/ (passo a passo no README).
dir_serie <- dir_brutos(FONTE, "serie_historica")
exportacoes <- list.files(dir_serie, pattern = "[.](csv|txt)$", ignore.case = TRUE)
if (length(exportacoes)) {
  log_msg(length(exportacoes), " exportacao(oes) da Serie Historica SNIS em ", dir_serie)
} else {
  log_msg("Aviso: nenhuma exportacao da Serie Historica SNIS em ", dir_serie,
          ". Sem ela a base tratada cobre apenas o SINISA (2023 em diante). Veja o README.")
}

registrar_execucao(FONTE, "extracao", paste0(nrow(plano), " pacote(s) SINISA; ",
                                            length(exportacoes), " exportacao(oes) SNIS"))
