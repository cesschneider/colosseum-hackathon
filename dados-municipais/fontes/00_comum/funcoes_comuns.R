# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# ARQUIVO: funcoes_comuns.R
# PAPEL:   Biblioteca compartilhada por todas as fontes: ambiente, download
#          atomico com retentativas, leitura/gravacao de CSV, dicionario oficial
#          de municipios (IBGE, 5.570 municipios), helpers para as APIs SIDRA,
#          Ipeadata e SGS/BCB, validacao e gravacao das bases tratadas.
# USO:     source(file.path(<pasta 00_comum>, "funcoes_comuns.R"))
#          Todo script de fonte comeca com o bloco padrao (ver CONVENCOES.md).
# DEPENDENCIAS: R base + jsonlite + curl. data.table, readxl, xml2 e outros sao
#          opcionais e exigidos apenas pelas fontes que os usam.
# ------------------------------------------------------------------------------

# ---- 1. Localizacao e ambiente ----------------------------------------------

obter_dir_script <- function() {
  argumento <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(argumento)) {
    return(dirname(normalizePath(sub("^--file=", "", argumento[[1L]]),
                                 winslash = "/", mustWork = FALSE)))
  }
  for (quadro in rev(sys.frames())) {
    arquivo <- tryCatch(get("ofile", envir = quadro, inherits = FALSE),
                        error = function(e) NULL)
    if (is.character(arquivo) && length(arquivo) == 1L) {
      return(dirname(normalizePath(arquivo, winslash = "/", mustWork = FALSE)))
    }
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

.localizar_dir_comum <- function() {
  # 1) Este arquivo esta sendo carregado por source(): o quadro mais interno
  #    de source() guarda o caminho em `ofile`.
  for (quadro in rev(sys.frames())) {
    arquivo <- tryCatch(get("ofile", envir = quadro, inherits = FALSE), error = function(e) NULL)
    if (is.character(arquivo) && length(arquivo) == 1L && grepl("funcoes_comuns[.]R$", arquivo)) {
      return(dirname(normalizePath(arquivo, winslash = "/", mustWork = FALSE)))
    }
  }
  # 2) Script executado via Rscript dentro de fontes/<fonte>/ ou fontes/00_comum/.
  d <- obter_dir_script()
  if (file.exists(file.path(d, "config.R"))) return(d)
  if (file.exists(file.path(dirname(d), "00_comum", "config.R"))) return(file.path(dirname(d), "00_comum"))
  # 3) Variavel de ambiente com a raiz do projeto.
  raiz <- Sys.getenv("PAINEL_RAIZ", unset = "")
  if (nzchar(raiz) && file.exists(file.path(raiz, "fontes", "00_comum", "config.R"))) {
    return(file.path(raiz, "fontes", "00_comum"))
  }
  stop("Nao foi possivel localizar fontes/00_comum. Defina PAINEL_RAIZ.")
}
.DIR_COMUM <- .localizar_dir_comum()
source(file.path(.DIR_COMUM, "config.R"), local = FALSE, encoding = "UTF-8")

log_msg <- function(...) {
  message(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "), paste0(..., collapse = ""))
}

exigir_pacotes <- function(pacotes) {
  ausentes <- pacotes[!vapply(pacotes, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(ausentes)) {
    stop("Pacotes ausentes: ", paste(ausentes, collapse = ", "),
         ". Execute fontes/00_comum/instalar_dependencias.R.", call. = FALSE)
  }
  invisible(TRUE)
}

preparar_ambiente <- function(pacotes = character()) {
  options(scipen = 999, warn = 1, timeout = TIMEOUT_PADRAO, stringsAsFactors = FALSE)
  if (.Platform$OS.type == "windows") {
    for (loc in c("Portuguese_Brazil.utf8", "English_United States.utf8", ".UTF-8")) {
      atual <- suppressWarnings(try(Sys.setlocale("LC_CTYPE", loc), silent = TRUE))
      if (is.character(atual) && grepl("utf-?8|65001", atual, ignore.case = TRUE)) break
    }
  }
  exigir_pacotes(unique(c("jsonlite", "curl", pacotes)))
  for (d in c(DIR_AUXILIARES, DIR_BRUTOS, DIR_TRATADOS, DIR_PAINEL, DIR_LOGS)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(TRUE)
}

dir_brutos <- function(fonte, ...) {
  d <- file.path(DIR_BRUTOS, fonte, ...)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

dir_tratados <- function(fonte, ...) {
  d <- file.path(DIR_TRATADOS, fonte, ...)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

ler_booleano_env <- function(nome, padrao = FALSE) {
  toupper(trimws(Sys.getenv(nome, if (padrao) "TRUE" else "FALSE"))) %in%
    c("TRUE", "T", "1", "SIM", "S", "YES", "Y")
}

ano_inicial_efetivo <- function(ano_padrao_fonte) {
  # Respeita PAINEL_ANO_INICIAL (para testes) sem recuar antes do inicio da serie.
  if (is.na(ANO_INICIAL_GLOBAL)) return(as.integer(ano_padrao_fonte))
  max(as.integer(ano_padrao_fonte), ANO_INICIAL_GLOBAL)
}

# ---- 2. Rede: download atomico e leitura de URLs -----------------------------

.novo_handle <- function(timeout = TIMEOUT_PADRAO) {
  h <- curl::new_handle()
  curl::handle_setopt(h, followlocation = TRUE, timeout = timeout,
                      connecttimeout = 60L, ssl_verifypeer = TRUE)
  curl::handle_setheaders(h, `User-Agent` = USER_AGENT, Accept = "*/*")
  h
}

baixar_arquivo <- function(url, destino, reutilizar = REUTILIZAR_BRUTOS,
                           tentativas = TENTATIVAS_PADRAO, timeout = TIMEOUT_PADRAO,
                           tamanho_minimo = 1L, validador = NULL, quiet = FALSE) {
  # Baixa `url` para `destino` de forma atomica (.part -> destino), com
  # retentativas e validacao opcional. Se `reutilizar` e o arquivo ja existe e
  # passa no validador, nao baixa de novo. Retorna o caminho do destino.
  dir.create(dirname(destino), recursive = TRUE, showWarnings = FALSE)
  valido <- function(arquivo) {
    if (!file.exists(arquivo) || file.info(arquivo)$size < tamanho_minimo) return(FALSE)
    if (is.null(validador)) return(TRUE)
    isTRUE(tryCatch(validador(arquivo), error = function(e) FALSE))
  }
  if (reutilizar && valido(destino)) {
    if (!quiet) log_msg("Reutilizado: ", basename(destino))
    return(invisible(destino))
  }
  temporario <- paste0(destino, ".part")
  on.exit(if (file.exists(temporario)) unlink(temporario, force = TRUE), add = TRUE)
  erro_final <- NULL
  for (tentativa in seq_len(tentativas)) {
    resultado <- tryCatch({
      if (!quiet) log_msg("Baixando (", tentativa, "/", tentativas, "): ", url)
      curl::curl_download(url, temporario, handle = .novo_handle(timeout), quiet = TRUE)
      if (!valido(temporario)) stop("arquivo baixado invalido ou vazio")
      if (file.exists(destino)) unlink(destino, force = TRUE)
      if (!file.rename(temporario, destino)) {
        if (!file.copy(temporario, destino, overwrite = TRUE)) stop("falha ao gravar ", destino)
        unlink(temporario, force = TRUE)
      }
      TRUE
    }, error = function(e) e)
    if (isTRUE(resultado)) return(invisible(destino))
    erro_final <- conditionMessage(resultado)
    if (tentativa < tentativas) Sys.sleep(min(2 ^ tentativa, 15))
  }
  stop("Falha ao baixar ", url, ": ", erro_final, call. = FALSE)
}

obter_texto_url <- function(url, timeout = 120L, tentativas = TENTATIVAS_PADRAO) {
  erro_final <- NULL
  for (tentativa in seq_len(tentativas)) {
    resposta <- tryCatch(curl::curl_fetch_memory(url, handle = .novo_handle(timeout)),
                         error = function(e) e)
    if (!inherits(resposta, "error") && resposta$status_code < 400L) {
      return(rawToChar(resposta$content))
    }
    erro_final <- if (inherits(resposta, "error")) conditionMessage(resposta) else
      paste("HTTP", resposta$status_code)
    if (tentativa < tentativas) Sys.sleep(min(2 ^ tentativa, 15))
  }
  stop("Falha ao acessar ", url, ": ", erro_final, call. = FALSE)
}

obter_json_url <- function(url, timeout = 300L, ...) {
  texto <- obter_texto_url(url, timeout = timeout)
  Encoding(texto) <- "UTF-8"
  jsonlite::fromJSON(texto, ...)
}

listar_links_pagina <- function(url, padrao = NULL, timeout = 120L) {
  # Extrai os hrefs de uma pagina HTML (descoberta de arquivos em portais).
  html <- obter_texto_url(url, timeout = timeout)
  brutos <- regmatches(html, gregexpr("href=[\"'][^\"']+[\"']", html, perl = TRUE))[[1L]]
  links <- sub("^href=[\"']", "", sub("[\"']$", "", brutos))
  links <- unique(links)
  if (!is.null(padrao)) links <- links[grepl(padrao, links, ignore.case = TRUE, perl = TRUE)]
  links
}

descompactar_zip <- function(arquivo_zip, destino, membros = NULL, sobrescrever = TRUE) {
  dir.create(destino, recursive = TRUE, showWarnings = FALSE)
  utils::unzip(arquivo_zip, files = membros, exdir = destino, overwrite = sobrescrever)
  invisible(destino)
}

listar_membros_zip <- function(arquivo_zip) utils::unzip(arquivo_zip, list = TRUE)$Name

# ---- 3. CSV -------------------------------------------------------------------

escrever_csv <- function(x, destino) {
  dir.create(dirname(destino), recursive = TRUE, showWarnings = FALSE)
  temporario <- paste0(destino, ".part")
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::fwrite(x, temporario, sep = CSV_SEP, dec = CSV_DEC, na = "",
                       bom = FALSE, encoding = "UTF-8")
  } else {
    utils::write.table(x, temporario, sep = CSV_SEP, dec = CSV_DEC, na = "",
                       row.names = FALSE, qmethod = "double", fileEncoding = CSV_ENCODING)
  }
  if (file.exists(destino)) unlink(destino, force = TRUE)
  if (!file.rename(temporario, destino)) {
    if (!file.copy(temporario, destino, overwrite = TRUE)) stop("Nao foi possivel gravar: ", destino)
    unlink(temporario, force = TRUE)
  }
  invisible(destino)
}

ler_csv <- function(arquivo, sep = CSV_SEP, dec = CSV_DEC, encoding = "UTF-8",
                    colunas_texto = c("codigo_municipio", "codigo6", "cod_uf", "uf"), ...) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    cabecalho <- names(data.table::fread(arquivo, sep = sep, nrows = 0L, encoding = encoding))
    texto <- intersect(colunas_texto, cabecalho)
    return(data.table::fread(arquivo, sep = sep, dec = dec, encoding = encoding,
                             colClasses = if (length(texto)) list(character = texto) else NULL,
                             na.strings = c("", "NA"), ...))
  }
  utils::read.table(arquivo, sep = sep, dec = dec, header = TRUE, quote = "\"",
                    fileEncoding = encoding, stringsAsFactors = FALSE,
                    na.strings = c("", "NA"), check.names = FALSE, comment.char = "", ...)
}

# ---- 4. Texto -----------------------------------------------------------------

remover_acentos <- function(x) {
  if (requireNamespace("stringi", quietly = TRUE)) {
    return(stringi::stri_trans_general(x, "Latin-ASCII"))
  }
  iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
}

normalizar_nome <- function(x) {
  # Chave textual para juncoes por nome: minusculas, sem acentos, sem
  # pontuacao, espacos unicos. Ex.: "Sao Joao d'El Rei" -> "sao joao d el rei".
  x <- tolower(remover_acentos(as.character(x)))
  x <- gsub("[^a-z0-9 ]", " ", x)
  trimws(gsub(" +", " ", x))
}

MESES_PT <- c("janeiro", "fevereiro", "marco", "abril", "maio", "junho", "julho",
              "agosto", "setembro", "outubro", "novembro", "dezembro")

mes_pt_para_numero <- function(nome) {
  chave <- normalizar_nome(nome)
  # tolera grafias truncadas de portais ("maro" para marco)
  chave[chave == "maro"] <- "marco"
  match(chave, MESES_PT)
}

para_numero <- function(x) {
  # Converte texto numerico em formato brasileiro ou internacional para double.
  x <- trimws(as.character(x))
  x[x %in% c("", "-", "...", "..", "X", "x", "NA", "n/a", "N/A")] <- NA_character_
  tem_virgula <- !is.na(x) & grepl(",", x, fixed = TRUE)
  x[tem_virgula] <- gsub(".", "", x[tem_virgula], fixed = TRUE)
  x[tem_virgula] <- gsub(",", ".", x[tem_virgula], fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

# ---- 5. Dicionario oficial de municipios (IBGE) --------------------------------

ARQUIVO_DICIONARIO_MUNICIPIOS <- file.path(DIR_AUXILIARES, "dicionario_municipios.csv")

construir_dicionario_municipios <- function(destino = ARQUIVO_DICIONARIO_MUNICIPIOS) {
  # Baixa a lista oficial dos 5.570 municipios (API de localidades do IBGE) e
  # grava o dicionario padrao do projeto. Chamado por 01_dicionario_municipios.R
  # e, automaticamente, por carregar_dicionario_municipios() quando ausente.
  log_msg("Baixando a lista oficial de municipios do IBGE.")
  bruto <- obter_json_url(URL_IBGE_LOCALIDADES, timeout = 300L)
  if (!is.data.frame(bruto) || nrow(bruto) < 5000L) {
    stop("Resposta inesperada da API de localidades do IBGE.")
  }
  pegar <- function(nome) if (nome %in% names(bruto)) bruto[[nome]] else NA
  dic <- data.frame(
    codigo_municipio = sprintf("%07d", as.integer(bruto[["municipio-id"]])),
    nome_municipio = as.character(bruto[["municipio-nome"]]),
    uf = as.character(bruto[["UF-sigla"]]),
    cod_uf = as.integer(bruto[["UF-id"]]),
    nome_uf = as.character(bruto[["UF-nome"]]),
    regiao = as.character(bruto[["regiao-nome"]]),
    codigo_microrregiao = as.integer(pegar("microrregiao-id")),
    nome_microrregiao = as.character(pegar("microrregiao-nome")),
    codigo_mesorregiao = as.integer(pegar("mesorregiao-id")),
    nome_mesorregiao = as.character(pegar("mesorregiao-nome")),
    codigo_regiao_imediata = as.integer(pegar("regiao-imediata-id")),
    nome_regiao_imediata = as.character(pegar("regiao-imediata-nome")),
    codigo_regiao_intermediaria = as.integer(pegar("regiao-intermediaria-id")),
    nome_regiao_intermediaria = as.character(pegar("regiao-intermediaria-nome")),
    stringsAsFactors = FALSE
  )
  dic$codigo6 <- substr(dic$codigo_municipio, 1L, 6L)
  dic$nome_normalizado <- normalizar_nome(dic$nome_municipio)
  dic <- dic[order(dic$codigo_municipio), ]
  if (anyDuplicated(dic$codigo_municipio)) stop("Codigos municipais duplicados na API do IBGE.")
  escrever_csv(dic, destino)
  log_msg("Dicionario gravado com ", nrow(dic), " municipios: ", destino)
  invisible(dic)
}

carregar_dicionario_municipios <- function(forcar = FALSE, somente_ufs_ativas = TRUE) {
  if (forcar || !file.exists(ARQUIVO_DICIONARIO_MUNICIPIOS)) {
    construir_dicionario_municipios()
  }
  dic <- as.data.frame(ler_csv(ARQUIVO_DICIONARIO_MUNICIPIOS))
  dic$codigo_municipio <- sprintf("%07d", as.integer(dic$codigo_municipio))
  dic$codigo6 <- substr(dic$codigo_municipio, 1L, 6L)
  if (somente_ufs_ativas) dic <- dic[dic$uf %in% UFS_ATIVAS$uf, , drop = FALSE]
  dic
}

padronizar_codigo7 <- function(x) {
  # Aceita numerico ou texto com 7 digitos; devolve texto com 7 digitos ou NA.
  x <- gsub("[^0-9]", "", as.character(x))
  x[!nzchar(x) | is.na(x)] <- NA_character_
  x <- ifelse(is.na(x), NA_character_, sprintf("%07d", as.integer(x)))
  x[!is.na(x) & !grepl("^[0-9]{7}$", x)] <- NA_character_
  x
}

codigo6_para_7 <- function(codigo6, dicionario = carregar_dicionario_municipios()) {
  # Converte codigos IBGE de 6 digitos (sem digito verificador, usados por
  # RAIS, DataSUS, SIM, BCB etc.) para 7 digitos via dicionario oficial.
  chave <- gsub("[^0-9]", "", as.character(codigo6))
  chave <- ifelse(nzchar(chave) & !is.na(chave), sprintf("%06d", as.integer(chave)), NA_character_)
  dicionario$codigo_municipio[match(chave, dicionario$codigo6)]
}

juntar_dicionario <- function(df, dicionario = carregar_dicionario_municipios(),
                              coluna_codigo = "codigo_municipio", manter_nao_encontrados = FALSE) {
  # Acrescenta nome_municipio e uf oficiais a partir do codigo de 7 digitos.
  df <- as.data.frame(df)
  df[[coluna_codigo]] <- padronizar_codigo7(df[[coluna_codigo]])
  idx <- match(df[[coluna_codigo]], dicionario$codigo_municipio)
  nao_encontrados <- unique(df[[coluna_codigo]][is.na(idx)])
  if (length(nao_encontrados)) {
    log_msg("Aviso: ", length(nao_encontrados), " codigo(s) fora do dicionario oficial",
            if (manter_nao_encontrados) " (mantidos)" else " (descartados)", ". Ex.: ",
            paste(head(nao_encontrados, 5L), collapse = ", "))
  }
  df$nome_municipio <- dicionario$nome_municipio[idx]
  df$uf <- dicionario$uf[idx]
  if (!manter_nao_encontrados) df <- df[!is.na(idx), , drop = FALSE]
  if (coluna_codigo != "codigo_municipio") df$codigo_municipio <- df[[coluna_codigo]]
  df
}

juntar_por_nome_uf <- function(df, coluna_nome, coluna_uf,
                               dicionario = carregar_dicionario_municipios()) {
  # Para fontes sem codigo IBGE (ex.: SENATRAN, ANP): junta por nome
  # normalizado + UF. Devolve df com codigo_municipio (NA quando nao casou) e
  # informa a taxa de casamento.
  df <- as.data.frame(df)
  chave_df <- paste(normalizar_nome(df[[coluna_nome]]), toupper(trimws(df[[coluna_uf]])))
  chave_dic <- paste(dicionario$nome_normalizado, dicionario$uf)
  df$codigo_municipio <- dicionario$codigo_municipio[match(chave_df, chave_dic)]
  faltantes <- unique(chave_df[is.na(df$codigo_municipio)])
  log_msg("Juncao por nome+UF: ", sum(!is.na(df$codigo_municipio)), " de ", nrow(df),
          " linhas casadas; ", length(faltantes), " chave(s) sem correspondencia.")
  if (length(faltantes)) log_msg("Ex. sem correspondencia: ", paste(head(faltantes, 8L), collapse = " | "))
  df
}

uf_por_codigo <- function(codigo_municipio) {
  cod <- as.integer(substr(padronizar_codigo7(codigo_municipio), 1L, 2L))
  UFS$uf[match(cod, UFS$cod_uf)]
}

# ---- 6. APIs compartilhadas: SIDRA (IBGE), Ipeadata, SGS (BCB) ---------------

sidra_consultar <- function(tabela, variaveis, periodos = "all", classificacoes = "",
                            nivel = "n6", por_uf = TRUE, timeout = 600L) {
  # Consulta a API SIDRA (apisidra.ibge.gov.br/values) para todos os municipios
  # do Brasil, uma UF por vez (evita respostas gigantes e timeouts).
  # `classificacoes`: trecho de caminho como "/c81/0" ou "/c2/6794/c287/100362".
  # Retorna data.frame longo com as colunas nomeadas pelo cabecalho da API
  # (ex.: "Municipio (Codigo)", "Variavel", "Ano", "Valor").
  v <- paste(variaveis, collapse = ",")
  p <- paste(periodos, collapse = ",")
  montar_url <- function(localidade) {
    paste0(URL_SIDRA_VALUES, "/t/", tabela, "/", nivel, "/", localidade,
           "/v/", v, "/p/", p, classificacoes, "?formato=json")
  }
  ler_bloco <- function(url) {
    texto <- obter_texto_url(url, timeout = timeout)
    Encoding(texto) <- "UTF-8"
    bruto <- jsonlite::fromJSON(texto, simplifyVector = TRUE)
    if (!is.data.frame(bruto) || nrow(bruto) < 2L) return(NULL)
    cabecalho <- unlist(bruto[1L, ], use.names = FALSE)
    dados <- bruto[-1L, , drop = FALSE]
    names(dados) <- cabecalho
    rownames(dados) <- NULL
    dados
  }
  localidades <- if (por_uf && nivel == "n6") {
    paste0("in%20n3%20", UFS_ATIVAS$cod_uf)
  } else "all"
  blocos <- lapply(localidades, function(loc) {
    log_msg("SIDRA t", tabela, " v", v, " localidade ", utils::URLdecode(loc))
    ler_bloco(montar_url(loc))
  })
  blocos <- Filter(Negate(is.null), blocos)
  if (!length(blocos)) stop("A API SIDRA nao devolveu dados para a tabela ", tabela, ".")
  resultado <- do.call(rbind, blocos)
  rownames(resultado) <- NULL
  resultado
}

sidra_padronizar <- function(df) {
  # Renomeia as colunas padrao do SIDRA para o esquema do projeto e converte o
  # valor para numerico. Colunas de classificacao sao mantidas como estao.
  nomes <- names(df)
  nomes_ascii <- remover_acentos(nomes)
  achar <- function(padrao) {
    encontrado <- nomes[grepl(padrao, nomes_ascii, ignore.case = TRUE)]
    if (length(encontrado)) encontrado[[1L]] else NA_character_
  }
  col_cod <- achar("^Municipio \\(Codigo\\)$")
  col_nome <- achar("^Municipio$")
  col_var_cod <- achar("^Variavel \\(Codigo\\)$")
  col_var <- achar("^Variavel$")
  col_ano <- achar("^(Ano|Periodo|Mes|Trimestre) \\(Codigo\\)$")
  col_valor <- achar("^Valor$")
  col_unidade <- achar("^Unidade de Medida$")
  faltando <- c(col_cod, col_nome, col_var_cod, col_var, col_ano, col_valor)
  if (anyNA(faltando)) stop("Colunas padrao do SIDRA nao encontradas: ", paste(nomes, collapse = " | "))
  saida <- data.frame(
    codigo_municipio = padronizar_codigo7(df[[col_cod]]),
    nome_municipio = sub(" - [A-Z]{2}$", "", as.character(df[[col_nome]])),
    variavel_codigo = as.character(df[[col_var_cod]]),
    variavel = as.character(df[[col_var]]),
    periodo = as.character(df[[col_ano]]),
    unidade = if (!is.na(col_unidade)) as.character(df[[col_unidade]]) else NA_character_,
    valor = para_numero(df[[col_valor]]),
    stringsAsFactors = FALSE
  )
  saida$ano <- as.integer(substr(saida$periodo, 1L, 4L))
  descartar <- c(col_cod, col_nome, col_var_cod, col_var, col_ano, col_valor, col_unidade,
                 nomes[grepl("^Nivel Territorial|^Unidade de Medida \\(Codigo\\)|^(Ano|Periodo|Mes|Trimestre)$", nomes_ascii)])
  extras <- setdiff(nomes, descartar[!is.na(descartar)])
  for (e in extras) saida[[e]] <- df[[e]]
  saida
}

ipeadata_valores <- function(serie, timeout = 600L) {
  # Serie completa do Ipeadata (OData v4). Colunas: SERCODIGO, VALDATA,
  # VALVALOR, NIVNOME, TERCODIGO.
  url <- paste0(URL_IPEADATA_ODATA, "/ValoresSerie(SERCODIGO='", serie, "')")
  resposta <- obter_json_url(url, timeout = timeout)
  dados <- resposta$value
  if (is.null(dados) || !nrow(dados)) stop("Ipeadata sem valores para a serie ", serie, ".")
  dados
}

ipeadata_metadados <- function(serie) {
  url <- paste0(URL_IPEADATA_ODATA, "/Metadados(SERCODIGO='", serie, "')")
  obter_json_url(url)$value
}

ipeadata_municipal <- function(serie, timeout = 600L) {
  # Recorte municipal (nivel "Municipios") ja no esquema do projeto:
  # codigo_municipio, ano, mes, valor.
  dados <- ipeadata_valores(serie, timeout = timeout)
  nivel <- remover_acentos(as.character(dados$NIVNOME))
  municipal <- dados[nivel %in% c("Municipios", "Municipio"), , drop = FALSE]
  if (!nrow(municipal)) stop("A serie ", serie, " do Ipeadata nao possui nivel municipal.")
  data <- as.Date(substr(as.character(municipal$VALDATA), 1L, 10L))
  data.frame(
    serie = serie,
    codigo_municipio = padronizar_codigo7(municipal$TERCODIGO),
    ano = as.integer(format(data, "%Y")),
    mes = as.integer(format(data, "%m")),
    valor = suppressWarnings(as.numeric(municipal$VALVALOR)),
    stringsAsFactors = FALSE
  )
}

bcb_sgs <- function(serie, data_inicial = NULL, data_final = NULL) {
  # Serie do SGS/BCB (ex.: 433 = IPCA mensal). Retorna data.frame(data, valor).
  url <- paste0(URL_BCB_SGS, serie, "/dados?formato=json")
  if (!is.null(data_inicial)) url <- paste0(url, "&dataInicial=", format(as.Date(data_inicial), "%d/%m/%Y"))
  if (!is.null(data_final)) url <- paste0(url, "&dataFinal=", format(as.Date(data_final), "%d/%m/%Y"))
  dados <- obter_json_url(url)
  data.frame(data = as.Date(dados$data, "%d/%m/%Y"), valor = as.numeric(dados$valor))
}

deflator_ipca_anual <- function(ano_base, ano_inicial = 1995L) {
  # Fator para converter valores nominais de cada ano em reais de `ano_base`,
  # usando a media anual do indice IPCA (SGS 433 acumulado).
  ipca <- bcb_sgs(433L, data_inicial = as.Date(paste0(ano_inicial - 1L, "-12-01")))
  ipca <- ipca[order(ipca$data), ]
  ipca$indice <- cumprod(1 + ipca$valor / 100)
  ipca$ano <- as.integer(format(ipca$data, "%Y"))
  medias <- tapply(ipca$indice, ipca$ano, mean)
  saida <- data.frame(ano = as.integer(names(medias)),
                      fator = as.numeric(medias[as.character(ano_base)] / medias),
                      ano_base = ano_base)
  # O ano anterior a `ano_inicial` so tem dezembro (base do indice) e o ano
  # corrente e parcial: ambos nao representam uma media anual completa.
  saida <- saida[saida$ano >= ano_inicial, , drop = FALSE]
  saida$meses_no_ano <- as.integer(table(ipca$ano)[as.character(saida$ano)])
  rownames(saida) <- NULL
  saida
}

# ---- 7. Validacao e gravacao das bases tratadas -----------------------------

validar_base_tratada <- function(df, mensal = FALSE, minimo_municipios = 1000L) {
  df <- as.data.frame(df)
  chaves <- c("codigo_municipio", "ano", if (mensal) "mes")
  ausentes <- setdiff(c(CHAVES_MUNICIPAIS, if (mensal) "mes"), names(df))
  if (length(ausentes)) stop("Base tratada sem colunas obrigatorias: ", paste(ausentes, collapse = ", "))
  if (any(!grepl("^[0-9]{7}$", df$codigo_municipio))) stop("codigo_municipio deve ter 7 digitos.")
  if (anyDuplicated(df[chaves])) stop("Chave duplicada (", paste(chaves, collapse = " + "), ").")
  indicadores <- setdiff(names(df), c(CHAVES_MUNICIPAIS, "mes"))
  if (!length(indicadores)) stop("A base tratada nao possui colunas de indicadores.")
  vazias <- indicadores[vapply(indicadores, function(v) all(is.na(df[[v]])), logical(1L))]
  if (length(vazias)) log_msg("Aviso: indicadores totalmente vazios: ", paste(vazias, collapse = ", "))
  n_mun <- length(unique(df$codigo_municipio))
  if (nrow(UFS_ATIVAS) == nrow(UFS) && n_mun < minimo_municipios) {
    log_msg("Aviso: apenas ", n_mun, " municipios na base (cobertura nacional esperada).")
  }
  invisible(TRUE)
}

salvar_base_tratada <- function(fonte, df, nome = paste0(fonte, "_municipal"), mensal = FALSE) {
  validar_base_tratada(df, mensal = mensal)
  df <- as.data.frame(df)
  ordem <- c(CHAVES_MUNICIPAIS, if (mensal) "mes")
  df <- df[c(ordem, setdiff(names(df), ordem))]
  chaves_ordem <- if (mensal) list(df$codigo_municipio, df$ano, df$mes) else list(df$codigo_municipio, df$ano)
  df <- df[do.call(order, chaves_ordem), , drop = FALSE]
  rownames(df) <- NULL
  destino <- file.path(dir_tratados(fonte), paste0(nome, ".csv"))
  escrever_csv(df, destino)
  log_msg("Base tratada gravada: ", destino, " (", nrow(df), " linhas, ",
          length(unique(df$codigo_municipio)), " municipios, ",
          min(df$ano), "-", max(df$ano), ")")
  registrar_execucao(fonte, "tratamento", paste0(nome, ": ", nrow(df), " linhas"))
  invisible(destino)
}

salvar_dicionario_variaveis <- function(fonte, dicionario, nome = paste0(fonte, "_dicionario_variaveis")) {
  # Esquema: variavel, descricao, unidade, periodicidade, nivel, tabela, fonte_url
  # (tabela e fonte_url opcionais). Serve de catalogo para a aplicacao.
  dicionario <- as.data.frame(dicionario, stringsAsFactors = FALSE)
  obrigatorias <- c("variavel", "descricao", "unidade", "periodicidade")
  ausentes <- setdiff(obrigatorias, names(dicionario))
  if (length(ausentes)) stop("Dicionario de variaveis sem colunas: ", paste(ausentes, collapse = ", "))
  if (!"nivel" %in% names(dicionario)) dicionario$nivel <- "municipio"
  if (!"tabela" %in% names(dicionario)) dicionario$tabela <- NA_character_
  if (!"fonte_url" %in% names(dicionario)) dicionario$fonte_url <- NA_character_
  dicionario$fonte <- fonte
  dicionario <- dicionario[c("fonte", "tabela", "variavel", "descricao", "unidade",
                             "periodicidade", "nivel", "fonte_url")]
  destino <- file.path(dir_tratados(fonte), paste0(nome, ".csv"))
  escrever_csv(dicionario, destino)
  invisible(destino)
}

registrar_execucao <- function(fonte, etapa, detalhe = "") {
  dir.create(DIR_LOGS, recursive = TRUE, showWarnings = FALSE)
  destino <- file.path(DIR_LOGS, "execucoes.csv")
  linha <- data.frame(data_hora = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), fonte = fonte,
                      etapa = etapa, detalhe = detalhe, stringsAsFactors = FALSE)
  utils::write.table(linha, destino, sep = CSV_SEP, row.names = FALSE,
                     col.names = !file.exists(destino), append = file.exists(destino),
                     fileEncoding = "UTF-8", qmethod = "double")
  invisible(destino)
}
