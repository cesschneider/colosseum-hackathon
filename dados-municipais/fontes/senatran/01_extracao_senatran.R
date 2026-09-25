# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_senatran.R
# FONTE: SENATRAN / Ministerio dos Transportes - Frota de veiculos (RENAVAM)
# OBJETIVO: Descobrir, nas paginas anuais do portal, os arquivos mensais de
#           frota por municipio (por combustivel e por tipo de veiculo) e
#           preservar os brutos, sem transformar.
# COBERTURA: Brasil, todos os municipios; julho/2016 ate o mes mais recente
#            (2013-2015 e jan-jun/2016 estao em .zip/.mdb/.rar e nao sao lidos)
# PERIODICIDADE: mensal
# ENDPOINT: https://www.gov.br/transportes/pt-br/assuntos/transito/conteudo-Senatran/frota-de-veiculos-<ANO>
# SAIDAS: dados/brutos/senatran/combustivel_<ano>_<mes>.xlsx|xls
#         dados/brutos/senatran/tipo_<ano>_<mes>.xlsx|xls|csv
# COMO EXECUTAR: Rscript fontes/senatran/01_extracao_senatran.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "senatran"

ANO_INICIAL <- ano_inicial_efetivo(2016L)
URL_PAGINA <- "https://www.gov.br/transportes/pt-br/assuntos/transito/conteudo-Senatran/frota-de-veiculos-"
dir_saida <- dir_brutos(FONTE)

extrair <- function(x, padrao) {
  # Primeiro trecho de cada elemento de x que casa com o padrao (NA se nenhum).
  m <- regexpr(padrao, x, perl = TRUE)
  r <- rep(NA_character_, length(x))
  r[m > 0L] <- regmatches(x, m)
  r
}

classificar_links <- function(links) {
  # Identifica pelo nome do arquivo o conjunto (combustivel | tipo), o mes e o
  # ano de cada link. A nomenclatura do portal varia muito entre anos
  # (maiusculas, "copy_of_", meses abreviados, "Maro" para marco, sufixos
  # numericos, URLs sem extensao terminadas em "-xlsx"), por isso o nome e
  # normalizado antes das expressoes regulares.
  nome <- tolower(remover_acentos(utils::URLdecode(basename(sub("[?#].*$", "", links)))))
  ext <- tolower(tools::file_ext(nome))
  sem_ext <- !nzchar(ext) & grepl("-(xlsx|xls|csv)$", nome)
  ext[sem_ext] <- sub(".*-", "", nome[sem_ext])
  base <- sub("[.-](xlsx|xls|csv)$", "", nome)
  conjunto <- ifelse(grepl("combustivel", base), "combustivel",
                     ifelse(grepl("munic", base) &
                              !grepl("cep|cor|potencia|restricao|fab|especie|marca|eixo", base),
                            "tipo", NA_character_))
  ano <- as.integer(extrair(base, "20[0-9]{2}"))
  ano_curto <- as.integer(extrair(base, "(?<=[_-])[0-9]{2}$"))
  ano[is.na(ano)] <- 2000L + ano_curto[is.na(ano)]
  mes <- mes_pt_para_numero(extrair(base, paste(c(MESES_PT, "maro"), collapse = "|")))
  abreviado <- extrair(base, "(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)(?=[a-z]*[_-]*[0-9]{2})")
  mes[is.na(mes)] <- match(abreviado[is.na(mes)], substr(MESES_PT, 1L, 3L))
  plano <- data.frame(url = links, conjunto = conjunto, ano = ano, mes = mes, ext = ext,
                      stringsAsFactors = FALSE)
  plano[!is.na(plano$conjunto) & plano$ext %in% c("xlsx", "xls", "csv") &
          !is.na(plano$ano) & !is.na(plano$mes), , drop = FALSE]
}

validar_planilha <- function(arquivo) {
  # Evita guardar uma pagina HTML de erro no lugar da planilha.
  assinatura <- readBin(arquivo, "raw", 2L)
  switch(tolower(tools::file_ext(arquivo)),
         xlsx = identical(assinatura, as.raw(c(0x50, 0x4b))),
         xls = identical(assinatura, as.raw(c(0xd0, 0xcf))),
         !identical(assinatura[1L], charToRaw("<")))
}

# 1. Descoberta: uma pagina por ano; links absolutos para xlsx/xls/csv.
plano <- do.call(rbind, lapply(seq(ANO_INICIAL, ANO_ATUAL), function(ano) {
  links <- tryCatch(listar_links_pagina(paste0(URL_PAGINA, ano), padrao = "xls|csv"),
                    error = function(e) {
                      log_msg("Pagina de ", ano, " indisponivel: ", conditionMessage(e))
                      character()
                    })
  links <- links[grepl("^https?://", links)]
  candidatos <- classificar_links(links)
  log_msg("Pagina ", ano, ": ", length(links), " links, ", nrow(candidatos), " arquivos municipais reconhecidos")
  candidatos
}))
if (is.null(plano) || !nrow(plano)) stop("Nenhum arquivo de frota reconhecido nas paginas do portal.")

# 2. Um arquivo por conjunto-mes: preferencia xlsx > xls > csv quando o portal
#    publica variantes ("copy_of_", csv) do mesmo mes; nomes canonicos na saida.
plano <- plano[plano$ano >= ANO_INICIAL & plano$ano <= ANO_ATUAL, ]
plano <- plano[order(plano$conjunto, plano$ano, plano$mes, match(plano$ext, c("xlsx", "xls", "csv"))), ]
plano <- plano[!duplicated(plano[c("conjunto", "ano", "mes")]), ]
plano$destino <- file.path(dir_saida, sprintf("%s_%04d_%02d.%s", plano$conjunto, plano$ano, plano$mes, plano$ext))
for (cj in c("combustivel", "tipo")) {
  meses <- table(plano$ano[plano$conjunto == cj])
  log_msg("Meses por ano (", cj, "): ", paste(names(meses), meses, sep = "=", collapse = " "))
}

# 3. Download atomico com reutilizacao (meses de anos encerrados nao mudam; o
#    ano corrente e sempre rebaixado). Falhas isoladas nao interrompem a coleta.
falhas <- character()
for (i in seq_len(nrow(plano))) {
  reutilizar <- REUTILIZAR_BRUTOS && plano$ano[i] < ANO_ATUAL
  ok <- tryCatch({
    baixar_arquivo(plano$url[i], plano$destino[i], reutilizar = reutilizar,
                   tamanho_minimo = 50000L, validador = validar_planilha)
    TRUE
  }, error = function(e) {
    log_msg("Falha: ", conditionMessage(e))
    FALSE
  })
  if (!ok) falhas <- c(falhas, basename(plano$destino[i]))
}
if (length(falhas)) log_msg("Arquivos nao obtidos (", length(falhas), "): ", paste(falhas, collapse = ", "))

registrar_execucao(FONTE, "extracao",
                   paste0(nrow(plano) - length(falhas), " de ", nrow(plano), " arquivos em ", dir_saida))
