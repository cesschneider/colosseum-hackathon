# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_bcb_estban.R
# FONTE: Banco Central do Brasil - ESTBAN (Estatistica Bancaria Mensal por
#        Municipio, documento 4500)
# OBJETIVO: Descobrir no catalogo oficial do site do BCB os arquivos mensais do
#           ESTBAN municipal e baixa-los sem transformar (um arquivo por mes,
#           todos os municipios do Brasil). Arquivos ja baixados sao
#           reutilizados quando o tamanho confere com o catalogo.
# COBERTURA: Brasil, todos os municipios com agencia bancaria; 2000-01 ate o
#            mes mais recente publicado (o catalogo remonta a 1988-07).
# PERIODICIDADE: mensal
# ENDPOINT: https://www.bcb.gov.br/api/servico/sitebcb/Documentos/byListGuid?
#           tronco=estatisticas&guidLista=f6391806-fd85-43af-acf1-c86d5b8dd6df&
#           ordem=DataDocumento%20desc&pasta=municipio  (catalogo JSON)
#           https://www.bcb.gov.br/content/estatisticas/estatistica_bancaria_estban/municipio/
#           AAAAMM_ESTBAN.ZIP | AAAAMM_ESTBAN.csv | AAAAMM_ESTBAN.csv.zip
# SAIDAS: dados/brutos/bcb_estban/AAAAMM_ESTBAN.<ZIP|csv|csv.zip>
# COMO EXECUTAR: Rscript fontes/bcb_estban/01_extracao_bcb_estban.R
#   Para testes: PAINEL_ANO_INICIAL=2023 (limita os meses baixados)
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "bcb_estban"

URL_BCB <- "https://www.bcb.gov.br"
URL_CATALOGO_ESTBAN <- paste0(
  URL_BCB, "/api/servico/sitebcb/Documentos/byListGuid?tronco=estatisticas",
  "&guidLista=f6391806-fd85-43af-acf1-c86d5b8dd6df&ordem=DataDocumento%20desc&pasta=municipio"
)
DIRETORIO_ESTBAN <- "/content/estatisticas/estatistica_bancaria_estban/municipio/"
ANO_INICIAL <- ano_inicial_efetivo(2000L)
dir_saida <- dir_brutos(FONTE)

# 1. Catalogo oficial (dinamico): registra corretamente as transicoes de
#    formato (ZIP historico, CSV direto em 2023-01, csv.zip desde 2023-02)
#    sem precisar tentar meses futuros.
log_msg("Consultando o catalogo oficial do ESTBAN municipal.")
catalogo <- obter_json_url(URL_CATALOGO_ESTBAN)$conteudo
if (!is.data.frame(catalogo) || !nrow(catalogo)) stop("O catalogo do ESTBAN retornou vazio.")
catalogo <- catalogo[grepl("^[0-9]{6}_ESTBAN([.]csv)?([.]zip)?$", catalogo$Nome, ignore.case = TRUE), ]
catalogo$periodo <- substr(catalogo$Nome, 1L, 6L)
catalogo$ano <- as.integer(substr(catalogo$periodo, 1L, 4L))
catalogo <- catalogo[catalogo$ano >= ANO_INICIAL, ]
catalogo <- catalogo[order(catalogo$periodo), ]
if (!nrow(catalogo)) stop("Nenhum arquivo do ESTBAN a partir de ", ANO_INICIAL, " no catalogo.")
if (anyDuplicated(catalogo$periodo)) stop("O catalogo possui mais de um arquivo para o mesmo mes.")
if (!all(startsWith(catalogo$Url, DIRETORIO_ESTBAN))) {
  stop("O catalogo retornou arquivo fora do diretorio oficial do ESTBAN municipal.")
}
esperados <- format(seq(as.Date(paste0(ANO_INICIAL, "-01-01")),
                        as.Date(paste0(max(catalogo$periodo), "01"), "%Y%m%d"), by = "month"), "%Y%m")
faltantes <- setdiff(esperados, catalogo$periodo)
if (length(faltantes)) log_msg("Aviso: meses sem arquivo no catalogo: ", paste(faltantes, collapse = ", "))

catalogo$url <- paste0(URL_BCB, catalogo$Url)
catalogo$tamanho <- suppressWarnings(as.numeric(catalogo$Tamanho))
catalogo$destino <- file.path(dir_saida, catalogo$Nome)
log_msg(nrow(catalogo), " meses no catalogo (", min(catalogo$periodo), " a ", max(catalogo$periodo),
        "), ~", round(sum(catalogo$tamanho, na.rm = TRUE) / 1e6), " MB no total.")

# 2. Download atomico. Um arquivo local e reutilizado somente se o tamanho
#    confere com o catalogo: se o BCB republicar um mes, ele e rebaixado.
validar_estban <- function(arquivo) {
  # Recebe o .part ainda sem renomear: identifica ZIP pela assinatura "PK".
  if (identical(readBin(arquivo, "raw", n = 2L), charToRaw("PK"))) {
    return(any(grepl("[.]csv$", listar_membros_zip(arquivo), ignore.case = TRUE)))
  }
  grepl("ESTBAN", readLines(arquivo, n = 1L, warn = FALSE), ignore.case = TRUE)
}
baixados <- 0L
for (i in seq_len(nrow(catalogo))) {
  mesmo_tamanho <- file.exists(catalogo$destino[i]) &&
    (is.na(catalogo$tamanho[i]) || file.info(catalogo$destino[i])$size == catalogo$tamanho[i])
  reutilizar <- REUTILIZAR_BRUTOS && mesmo_tamanho
  if (!reutilizar) {
    log_msg("Baixando ", catalogo$periodo[i], ": ", catalogo$Nome[i])
    baixados <- baixados + 1L
  }
  baixar_arquivo(catalogo$url[i], catalogo$destino[i], reutilizar = reutilizar,
                 validador = validar_estban, quiet = TRUE)
}

log_msg("Extracao concluida: ", nrow(catalogo), " meses em ", dir_saida, " (", baixados, " baixados agora).")
registrar_execucao(FONTE, "extracao", paste0(nrow(catalogo), " meses (", min(catalogo$periodo), "-",
                                              max(catalogo$periodo), "); ", baixados, " baixados"))
