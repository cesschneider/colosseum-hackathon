# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_anatel.R
# FONTE: Anatel - Acessos de Banda Larga Fixa (dados abertos) e Ipeadata/IBGE -
#        populacao residente municipal (series ESTIMA_PO e POPTOT)
# OBJETIVO: Baixar e preservar o zip oficial da Anatel (acessos mensais por
#           municipio, prestadora, tecnologia etc.) e as series de populacao
#           usadas para calcular a densidade por 100 habitantes. Nada e
#           transformado aqui.
# COBERTURA: Brasil, todos os municipios; 2007 (trimestral ate 2010, mensal
#            desde 2011) ate o mes mais recente publicado.
# PERIODICIDADE: mensal na fonte; a base tratada e anual.
# ENDPOINT: https://www.anatel.gov.br/dadosabertos/paineis_de_dados/acessos/acessos_banda_larga_fixa.zip
#           https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='ESTIMA_PO')
#           https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='POPTOT')
# SAIDAS: dados/brutos/anatel/acessos_banda_larga_fixa.zip   (~1 GB)
#         dados/brutos/anatel/ipeadata_ESTIMA_PO.csv, ipeadata_POPTOT.csv
# COMO EXECUTAR: Rscript fontes/anatel/01_extracao_anatel.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "anatel"

URL_ZIP_ANATEL <- "https://www.anatel.gov.br/dadosabertos/paineis_de_dados/acessos/acessos_banda_larga_fixa.zip"
SERIES_POPULACAO <- c("ESTIMA_PO", "POPTOT")
dir_saida <- dir_brutos(FONTE)

# 1. Zip oficial da Anatel (~1 GB, atualizado mensalmente com toda a serie).
#    A copia local e reutilizada quando o servidor nao informa uma data de
#    modificacao mais recente que o download local (evita rebaixar 1 GB).
data_modificacao_remota <- function(url) {
  h <- curl::new_handle(nobody = TRUE, followlocation = TRUE, timeout = 120L)
  curl::handle_setheaders(h, `User-Agent` = USER_AGENT)
  resposta <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) NULL)
  if (is.null(resposta) || resposta$status_code >= 400L) return(NA)
  texto <- curl::parse_headers_list(resposta$headers)[["last-modified"]]
  partes <- regmatches(texto, regexec("([0-9]{1,2}) ([A-Za-z]{3}) ([0-9]{4}) ([0-9:]{8})", texto))[[1L]]
  if (length(partes) != 5L) return(NA)
  as.POSIXct(sprintf("%s-%02d-%02d %s", partes[4L], match(partes[3L], month.abb),
                     as.integer(partes[2L]), partes[5L]), tz = "GMT")
}

destino_zip <- file.path(dir_saida, "acessos_banda_larga_fixa.zip")
reutilizar_zip <- REUTILIZAR_BRUTOS && file.exists(destino_zip)
if (reutilizar_zip) {
  remota <- data_modificacao_remota(URL_ZIP_ANATEL)
  if (!is.na(remota) && remota > file.mtime(destino_zip)) {
    log_msg("O zip da Anatel foi atualizado na fonte em ", format(remota, "%Y-%m-%d"), "; sera rebaixado.")
    reutilizar_zip <- FALSE
  }
}
validar_zip_anatel <- function(arquivo) {
  any(grepl("^Acessos_Banda_Larga_Fixa_.*[.]csv$", listar_membros_zip(arquivo), ignore.case = TRUE))
}
if (!reutilizar_zip) log_msg("Baixando o zip da Anatel (~1 GB; pode levar varios minutos).")
baixar_arquivo(URL_ZIP_ANATEL, destino_zip, reutilizar = reutilizar_zip, timeout = 4L * 3600L,
               tamanho_minimo = 1e8, validador = validar_zip_anatel)
membros <- listar_membros_zip(destino_zip)
log_msg("Zip preservado com ", length(membros), " arquivos (",
        round(file.info(destino_zip)$size / 1e6), " MB): ", destino_zip)

# 2. Populacao municipal do Ipeadata (recorte municipal ja no esquema do
#    projeto). As series sao pequenas e podem ser revisadas pelo IBGE, por isso
#    sao rebaixadas a cada execucao, exceto quando ja baixadas hoje.
for (serie in SERIES_POPULACAO) {
  destino <- file.path(dir_saida, paste0("ipeadata_", serie, ".csv"))
  baixado_hoje <- file.exists(destino) && format(file.mtime(destino), "%Y-%m-%d") == format(Sys.Date(), "%Y-%m-%d")
  if (REUTILIZAR_BRUTOS && baixado_hoje) {
    log_msg("Reutilizado (baixado hoje): ", basename(destino))
    next
  }
  log_msg("Baixando a serie ", serie, " do Ipeadata.")
  populacao <- ipeadata_municipal(serie)
  if (nrow(populacao) < 5000L) stop("A serie ", serie, " retornou poucos registros municipais (", nrow(populacao), ").")
  escrever_csv(populacao, destino)
  log_msg(serie, ": ", nrow(populacao), " registros, anos ", min(populacao$ano), "-", max(populacao$ano), ".")
}

registrar_execucao(FONTE, "extracao", paste0("zip com ", length(membros), " arquivos + ",
                                              length(SERIES_POPULACAO), " series de populacao em ", dir_saida))
