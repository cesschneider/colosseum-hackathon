# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_mapbiomas.R
# FONTE: MapBiomas Brasil - Estatisticas de cobertura e uso da terra (colecao vigente)
# OBJETIVO: Descobrir, na pagina oficial de estatisticas, a planilha municipal
#           da colecao vigente (hospedada no Google Drive), baixa-la e
#           preserva-la sem transformar.
# COBERTURA: Brasil, todos os municipios; 1985 ate o ultimo ano da colecao.
# PERIODICIDADE: anual (cada colecao nova reprocessa toda a serie).
# ENDPOINT: https://brasil.mapbiomas.org/estatisticas/ (descoberta do link) e
#           https://drive.usercontent.google.com/download?id=<id>&export=download&confirm=t
# SAIDAS: dados/brutos/mapbiomas/mapbiomas_cobertura_municipios_col<colecao>.xlsx
# COMO EXECUTAR: Rscript fontes/mapbiomas/01_extracao_mapbiomas.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "mapbiomas"

URL_PAGINA <- "https://brasil.mapbiomas.org/estatisticas/"
# Reserva usada quando a descoberta na pagina falha: id do Google Drive e numero
# da colecao (conferidos em setembro de 2026 para a Colecao 11). Podem ser
# sobrescritos por variaveis de ambiente quando a colecao mudar.
ID_PADRAO      <- Sys.getenv("PAINEL_MAPBIOMAS_DRIVE_ID", unset = "1otOqymHuixvkRGVl65zTTNyfaHo46Gqk")
COLECAO_PADRAO <- Sys.getenv("PAINEL_MAPBIOMAS_COLECAO", unset = "11")

texto_normalizado <- function(html) {
  # Remove tags e acentos, poe em minusculas e compacta espacos.
  x <- gsub("<[^>]+>", " ", html, perl = TRUE)
  x <- gsub("&#0?38;|&amp;", "&", x, perl = TRUE)
  tolower(gsub("[[:space:]]+", " ", remover_acentos(x)))
}

descobrir_fonte_mapbiomas <- function(pagina = URL_PAGINA) {
  # Procura o link do Google Drive cujo contexto (linha da tabela de downloads
  # ou o entorno do link) fala em municipios, cobertura e biomas; extrai o id
  # do arquivo e o numero da colecao. Retorna NULL quando nao encontra.
  html <- tryCatch(obter_texto_url(pagina), error = function(e) NULL)
  if (is.null(html)) return(NULL)
  Encoding(html) <- "UTF-8"
  padrao_link <- "href=[\"'][^\"']*(drive\\.google|drive\\.usercontent)[^\"']*[\"']"
  blocos <- regmatches(html, gregexpr("(?s)<tr\\b.*?</tr>", html, perl = TRUE))[[1L]]
  posicoes <- gregexpr(padrao_link, html, perl = TRUE)[[1L]]
  if (posicoes[[1L]] != -1L) {
    blocos <- c(blocos, vapply(posicoes, function(p) substr(html, max(1L, p - 1500L), p + 300L), character(1L)))
  }
  for (bloco in blocos) {
    link <- regmatches(bloco, regexpr(padrao_link, bloco, perl = TRUE))
    if (!length(link)) next
    texto <- texto_normalizado(bloco)
    if (!(grepl("municip", texto) && grepl("cobertura|coverage", texto) && grepl("bioma|biome", texto))) next
    id <- sub(".*(?:[?&]id=|/d/)([A-Za-z0-9_-]{20,}).*", "\\1", link, perl = TRUE)
    if (identical(id, link)) next
    m <- regmatches(texto, regexpr("(colecao|collection|col[.]?) ?[0-9]+(?:[.][0-9]+)?", texto, perl = TRUE))
    colecao <- if (length(m)) sub(".*?([0-9]+(?:[.][0-9]+)?)$", "\\1", m, perl = TRUE) else NA_character_
    return(list(id = id, colecao = colecao, descoberta = "pagina_oficial"))
  }
  NULL
}

e_xlsx <- function(arquivo) {
  # A planilha nacional tem dezenas de MB e e um pacote OOXML (zip: bytes "PK").
  # Paginas HTML devolvidas pelo Drive (aviso de antivirus, cota) sao recusadas.
  if (file.info(arquivo)$size < 1e6) return(FALSE)
  con <- file(arquivo, "rb")
  on.exit(close(con), add = TRUE)
  identical(readBin(con, "raw", 2L), as.raw(c(0x50, 0x4B)))
}

# 1. Descoberta do arquivo da colecao vigente
fonte <- descobrir_fonte_mapbiomas()
if (is.null(fonte)) {
  log_msg("Aviso: descoberta na pagina oficial falhou; usando o id de reserva (colecao ", COLECAO_PADRAO, ").")
  fonte <- list(id = ID_PADRAO, colecao = COLECAO_PADRAO, descoberta = "reserva")
}
if (is.na(fonte$colecao)) fonte$colecao <- COLECAO_PADRAO
log_msg("Fonte: colecao ", fonte$colecao, ", id ", fonte$id, " (", fonte$descoberta, ").")

# 2. Download atomico com reutilizacao. O nome guarda a colecao: uma colecao nova
#    gera um arquivo novo e o anterior fica preservado.
url <- paste0("https://drive.usercontent.google.com/download?id=", fonte$id, "&export=download&confirm=t")
destino <- file.path(dir_brutos(FONTE), sprintf("mapbiomas_cobertura_municipios_col%s.xlsx",
                                                gsub("[^0-9A-Za-z.]", "_", fonte$colecao)))
baixar_arquivo(url, destino, tamanho_minimo = 1e6, validador = e_xlsx)
log_msg("Bruto disponivel: ", destino, " (", round(file.info(destino)$size / 1e6, 1), " MB)")

registrar_execucao(FONTE, "extracao", paste0("colecao ", fonte$colecao, " (", fonte$descoberta, "): ", basename(destino)))
