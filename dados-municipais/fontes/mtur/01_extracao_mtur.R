# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_mtur.R
# FONTE: Ministerio do Turismo - Cadastur / Dados Abertos (meios de hospedagem
#        e guias de turismo)
# OBJETIVO: Descobrir no catalogo CKAN os recursos anuais/trimestrais de cada
#           dataset e baixar um retrato do cadastro por ano, sem transformar.
# COBERTURA: Brasil, todos os municipios; 2006 ate o ano corrente
# PERIODICIDADE: anual (recursos anuais ate 2015; trimestrais desde 2016 - usa-se
#                o ultimo trimestre publicado de cada ano)
# ENDPOINT: https://dados.turismo.gov.br/api/3/action/package_show?id=meios-de-hospedagem
#           https://dados.turismo.gov.br/api/3/action/package_show?id=prestadores-de-servicos-turisticos-guia-turismo_2
# SAIDAS: dados/brutos/mtur/mtur_<hospedagem|guias>_<ANO>_<anual|t1..t4>.<csv|xls|xlsx>
# COMO EXECUTAR: Rscript fontes/mtur/01_extracao_mtur.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "mtur"

ANO_INICIAL <- ano_inicial_efetivo(2006L)
URL_CKAN <- "https://dados.turismo.gov.br/api/3/action/package_show?id="
CONJUNTOS <- data.frame(
  tipo = c("hospedagem", "guias"),
  id = c("meios-de-hospedagem", "prestadores-de-servicos-turisticos-guia-turismo_2"),
  stringsAsFactors = FALSE
)
dir_saida <- dir_brutos(FONTE)

# 1. Descoberta via CKAN. Cada dataset lista um recurso por ano (2006-2015) ou
#    por trimestre (2016 em diante), em CSV, XLS ou XLSX, com nomes como "2010",
#    "Quarto Trimestre de 2024". Para cada ano fica o recurso anual ou, na falta
#    dele, o trimestre mais recente (retrato do cadastro no fim do ano; no ano
#    corrente, o ultimo trimestre publicado). Recursos repetidos do mesmo
#    periodo: vale o de modificacao mais recente.
extrair_ano <- function(texto) {
  pos <- regexpr("20[0-9]{2}", texto)
  ifelse(pos > 0L, suppressWarnings(as.integer(substr(texto, pos, pos + 3L))), NA_integer_)
}
extrair_trimestre <- function(texto) {
  chave <- normalizar_nome(texto)
  ordinais <- c("primeiro|1o|1", "segundo|2o|2", "terceiro|3o|3", "quarto|4o|4")
  trimestre <- rep(5L, length(chave))                       # 5 = recurso anual
  for (t in 1:4) trimestre[grepl(paste0("^(", ordinais[t], ") trimestre"), chave)] <- t
  trimestre
}
selecionar_recursos <- function(tipo, id) {
  resposta <- obter_json_url(paste0(URL_CKAN, id))
  recursos <- resposta$result$resources
  if (!isTRUE(resposta$success) || !is.data.frame(recursos) || !nrow(recursos)) {
    stop("Catalogo CKAN sem recursos para ", id)
  }
  nome <- trimws(as.character(recursos$name))
  url <- as.character(recursos$url)
  ano <- extrair_ano(nome)
  ano[is.na(ano)] <- extrair_ano(basename(url))[is.na(ano)]
  candidatos <- data.frame(
    tipo = tipo, nome = nome, url = url, ano = ano,
    extensao = tolower(sub("^.*[.]([A-Za-z0-9]+)$", "\\1", sub("[?].*$", "", url))),
    trimestre = extrair_trimestre(nome),
    modificado = as.character(recursos$last_modified %||% ""),
    stringsAsFactors = FALSE
  )
  candidatos <- candidatos[!is.na(candidatos$ano) & candidatos$ano >= ANO_INICIAL &
                             candidatos$extensao %in% c("csv", "xls", "xlsx"), , drop = FALSE]
  if (!nrow(candidatos)) stop("Nenhum recurso utilizavel no catalogo de ", id)
  candidatos <- candidatos[order(candidatos$ano, -candidatos$trimestre, -xtfrm(candidatos$modificado)), ]
  candidatos <- candidatos[!duplicated(candidatos$ano), , drop = FALSE]
  periodo <- ifelse(candidatos$trimestre == 5L, "anual", paste0("t", candidatos$trimestre))
  candidatos$destino <- file.path(dir_saida, sprintf("mtur_%s_%d_%s.%s", tipo, candidatos$ano,
                                                     periodo, candidatos$extensao))
  candidatos
}
plano <- do.call(rbind, Map(selecionar_recursos, CONJUNTOS$tipo, CONJUNTOS$id))
rownames(plano) <- NULL
log_msg(nrow(plano), " recursos selecionados (", min(plano$ano), "-", max(plano$ano), ").")

# Validador por formato: rejeita paginas HTML de erro e planilhas corrompidas.
validar_arquivo_mtur <- function(arquivo, extensao) {
  if (file.info(arquivo)$size < 1000) return(FALSE)
  inicio <- readBin(arquivo, "raw", n = 4096L)
  switch(extensao,
    csv = any(inicio == as.raw(59L)) && inicio[1L] != as.raw(60L),   # tem ';' e nao comeca com '<'
    xlsx = nrow(utils::unzip(arquivo, list = TRUE)) > 0L,
    xls = identical(inicio[1:4], as.raw(c(0xd0, 0xcf, 0x11, 0xe0))),  # assinatura OLE2
    FALSE)
}

# 2. Download atomico com reutilizacao: anos encerrados nao mudam (para forcar
#    uma republicacao, use PAINEL_REBAIXAR=TRUE); o ano corrente e sempre
#    rebaixado porque ganha um novo trimestre a cada publicacao. Versoes
#    antigas do mesmo tipo-ano (outro trimestre ou formato) sao removidas.
for (i in seq_len(nrow(plano))) {
  log_msg(plano$tipo[i], " ", plano$ano[i], " <- ", plano$nome[i])
  baixar_arquivo(plano$url[i], plano$destino[i],
                 reutilizar = REUTILIZAR_BRUTOS && plano$ano[i] < ANO_ATUAL,
                 validador = function(f) validar_arquivo_mtur(f, plano$extensao[i]))
  obsoletos <- list.files(dir_saida, pattern = sprintf("^mtur_%s_%d_", plano$tipo[i], plano$ano[i]),
                          full.names = TRUE)
  unlink(setdiff(obsoletos, plano$destino[i]))
}

registrar_execucao(FONTE, "extracao", paste0(nrow(plano), " arquivos em ", dir_saida))
