# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_anp.R
# FONTE: ANP - Dados abertos: vendas anuais de combustiveis por municipio e
#        Levantamento de Precos de Combustiveis (serie historica semestral)
# OBJETIVO: Baixar e preservar os brutos, sem transformar.
# COBERTURA: Brasil, todos os municipios; vendas 1990 ate o ultimo ano
#            publicado; precos 2013 (configuravel) ate o ultimo semestre.
# PERIODICIDADE: anual (vendas) | semanal por posto, agregada a mensal (precos)
# ENDPOINT: https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/vendas-de-derivados-de-petroleo-e-biocombustiveis
#           https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/serie-historica-de-precos-de-combustiveis
# SAIDAS: dados/brutos/anp/vendas/vendas_<produto>.csv
#         dados/brutos/anp/precos/precos_<ca|glp>_<ano>_<semestre>.zip|csv
# COMO EXECUTAR: Rscript fontes/anp/01_extracao_anp.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "anp"

ANO_INICIAL_PRECOS <- ano_inicial_efetivo(2013L)
URL_VENDAS <- "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/vdpb/vaehdpm/%s/vendas-anuais-de-%s-por-municipio.csv"
PRODUTOS_VENDAS <- c("etanol-hidratado", "gasolina-c", "oleo-diesel", "glp", "oleo-combustivel",
                     "gasolina-de-aviacao", "querosene-de-aviacao", "querosene-iluminante", "asfalto")
URL_PAGINA_PRECOS <- "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/serie-historica-de-precos-de-combustiveis"
URL_PRECOS_MODELO <- "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/shpc/dsas/%s/%s-%d-%02d.%s"
dir_vendas <- dir_brutos(FONTE, "vendas")
dir_precos <- dir_brutos(FONTE, "precos")

validar_bruto <- function(arquivo) {
  # zip comeca com "PK"; csv nao pode ser uma pagina HTML de erro.
  assinatura <- readBin(arquivo, "raw", 2L)
  if (grepl("[.]zip$", arquivo)) identical(assinatura, as.raw(c(0x50, 0x4b))) else !identical(assinatura[1L], charToRaw("<"))
}

# 1. Vendas anuais por municipio: um CSV acumulado (1990 em diante) por
#    produto, atualizado uma vez ao ano -> rebaixado se tiver mais de 30 dias.
for (produto in PRODUTOS_VENDAS) {
  destino <- file.path(dir_vendas, paste0("vendas_", produto, ".csv"))
  recente <- file.exists(destino) && as.numeric(Sys.time() - file.mtime(destino), units = "days") < 30
  ok <- tryCatch({
    baixar_arquivo(sprintf(URL_VENDAS, produto, produto), destino, reutilizar = REUTILIZAR_BRUTOS && recente,
                   tamanho_minimo = 10000L, validador = validar_bruto)
    TRUE
  }, error = function(e) {
    log_msg("Falha: ", conditionMessage(e))
    FALSE
  })
}

# 2. Precos: arquivos semestrais "ca" (combustiveis automotivos) e "glp",
#    descobertos na pagina (nomes fora do padrao, como precos-semestrais-ca.zip,
#    recebem o semestre anterior ao link precedente: a lista e decrescente).
#    Periodos ausentes na pagina tentam o padrao de URL (zip e depois csv).
links <- tryCatch(listar_links_pagina(URL_PAGINA_PRECOS, padrao = "shpc/dsas/(ca|glp)/"),
                  error = function(e) {
                    log_msg("Pagina de precos indisponivel: ", conditionMessage(e))
                    character()
                  })
links <- links[grepl("[.](zip|csv)$", links, ignore.case = TRUE)]
descoberto <- data.frame(url = links, conjunto = ifelse(grepl("/dsas/glp/", links), "glp", "ca"),
                         stringsAsFactors = FALSE)
periodo <- regmatches(basename(links), regexpr("20[0-9]{2}-?0[12]", basename(links)))
tem_periodo <- grepl("20[0-9]{2}-?0[12]", basename(links))
descoberto$ano <- NA_integer_
descoberto$sem <- NA_integer_
descoberto$ano[tem_periodo] <- as.integer(substr(periodo, 1L, 4L))
descoberto$sem[tem_periodo] <- as.integer(substr(periodo, nchar(periodo), nchar(periodo)))
for (i in which(!tem_periodo)) {
  if (i > 1L && descoberto$conjunto[i] == descoberto$conjunto[i - 1L] && !is.na(descoberto$ano[i - 1L])) {
    descoberto$ano[i] <- descoberto$ano[i - 1L] - (descoberto$sem[i - 1L] == 1L)
    descoberto$sem[i] <- 3L - descoberto$sem[i - 1L]
  }
}
descoberto <- descoberto[!is.na(descoberto$ano), ]

mes_atual <- as.integer(format(Sys.Date(), "%m"))
plano <- expand.grid(conjunto = c("ca", "glp"), ano = seq(ANO_INICIAL_PRECOS, ANO_ATUAL), sem = 1:2,
                     stringsAsFactors = FALSE)
plano <- plano[plano$ano < ANO_ATUAL | (plano$sem == 1L & mes_atual >= 7L), ]
plano <- plano[order(plano$conjunto, plano$ano, plano$sem), ]

falhas <- character()
for (i in seq_len(nrow(plano))) {
  cj <- plano$conjunto[i]; ano <- plano$ano[i]; sem <- plano$sem[i]
  candidatos <- unique(c(descoberto$url[descoberto$conjunto == cj & descoberto$ano == ano & descoberto$sem == sem],
                         sprintf(URL_PRECOS_MODELO, cj, cj, ano, sem, c("zip", "csv"))))
  destino_base <- file.path(dir_precos, sprintf("precos_%s_%d_%02d", cj, ano, sem))
  existente <- Sys.glob(paste0(destino_base, ".*"))
  if (REUTILIZAR_BRUTOS && ano < ANO_ATUAL && length(existente)) {
    log_msg("Reutilizado: ", basename(existente[1L]))
    next
  }
  obtido <- FALSE
  for (url in candidatos) {
    destino <- paste0(destino_base, ".", tolower(tools::file_ext(url)))
    obtido <- tryCatch({
      baixar_arquivo(url, destino, reutilizar = FALSE, tentativas = 2L, tamanho_minimo = 100000L,
                     validador = validar_bruto)
      TRUE
    }, error = function(e) {
      log_msg("Falha: ", conditionMessage(e))
      FALSE
    })
    if (obtido) break
  }
  if (!obtido) falhas <- c(falhas, basename(destino_base))
}
if (length(falhas)) log_msg("Periodos de precos nao obtidos (", length(falhas), "): ", paste(falhas, collapse = ", "))

registrar_execucao(FONTE, "extracao",
                   paste0(length(PRODUTOS_VENDAS), " arquivos de vendas; ", nrow(plano) - length(falhas), " de ",
                          nrow(plano), " arquivos semestrais de precos"))
