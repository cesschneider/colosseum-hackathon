# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_siconfi.R
# FONTE: Secretaria do Tesouro Nacional (STN) - API de Dados Abertos do SICONFI
# OBJETIVO: Baixar, ente a ente, a Declaracao de Contas Anuais (DCA: anexos I-C
#           receitas, I-D despesas por natureza e I-E despesas por funcao) e o
#           Anexo 06 do RREO (resultados nominal e primario) de todos os
#           municipios do Brasil, preservando as respostas brutas da API.
# COBERTURA: Brasil, todos os municipios (esfera "M"); DCA de 2013 e RREO de
#           2018 ate o ultimo exercicio encerrado (ano corrente - 1).
# PERIODICIDADE: anual (DCA) e bimestral (RREO; usa-se a posicao de
#           encerramento do exercicio: 6o bimestre ou 2o semestre).
# ENDPOINT: https://apidatalake.tesouro.gov.br/ords/siconfi/tt/{entes,dca,rreo}
# SAIDAS: dados/brutos/siconfi/entes.json
#         dados/brutos/siconfi/dca/<ano>/<cod_ibge>.json.gz
#         dados/brutos/siconfi/rreo/<ano>/<cod_ibge>.json.gz
# COMO EXECUTAR: Rscript fontes/siconfi/01_extracao_siconfi.R
#   Retomavel: arquivos ja gravados sao pulados. A API limita a ~1 requisicao
#   por segundo; a serie completa leva dezenas de horas (ver README).
#   Variaveis opcionais: PAINEL_UFS ("AC,RR"), PAINEL_ANO_INICIAL,
#   SICONFI_ANO_FINAL, SICONFI_ANO_INICIAL_RREO (padrao 2018),
#   SICONFI_PAUSA_SEGUNDOS (>= 1.05), SICONFI_RECONSULTAR_VAZIOS=TRUE
#   (reconsulta entes que estavam sem dados, ex.: declaracoes atrasadas).
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "siconfi"

URL_BASE <- "https://apidatalake.tesouro.gov.br/ords/siconfi/tt"
ANO_INICIAL <- ano_inicial_efetivo(2013L)
ANO_FINAL <- as.integer(Sys.getenv("SICONFI_ANO_FINAL", unset = as.character(ANO_ATUAL - 1L)))
# O Anexo 06 "acima da linha" (codigos usados no tratamento) existe a partir de 2018.
ANO_INICIAL_RREO <- max(ANO_INICIAL, as.integer(Sys.getenv("SICONFI_ANO_INICIAL_RREO", unset = "2018")))
# A documentacao limita o uso a uma requisicao por segundo: pausa minima de 1,05 s.
PAUSA_SEGUNDOS <- max(1.05, as.numeric(Sys.getenv("SICONFI_PAUSA_SEGUNDOS", unset = "1.10")))
TIMEOUT_REQUISICAO <- 180L
MAX_TENTATIVAS <- 3L
MAX_FALHAS_SEGUIDAS <- 5L
RECONSULTAR_VAZIOS <- ler_booleano_env("SICONFI_RECONSULTAR_VAZIOS", FALSE)
TAMANHO_VAZIO <- 400L   # arquivos sem itens ("items": []) ficam abaixo disto, em bytes
if (is.na(ANO_FINAL) || ANO_FINAL < ANO_INICIAL) stop("Janela de exercicios invalida: ", ANO_INICIAL, "-", ANO_FINAL)
dir_saida <- dir_brutos(FONTE)

# ---- 1. Cliente da API: rate limiter, retentativas com backoff e paginacao ----
montar_url <- function(endpoint, parametros = list()) {
  url <- paste0(URL_BASE, "/", endpoint)
  if (!length(parametros)) return(url)
  valores <- vapply(parametros, function(v) utils::URLencode(as.character(v), reserved = TRUE), character(1L))
  paste0(url, "?", paste0(names(valores), "=", valores, collapse = "&"))
}

empilhar <- function(partes) {
  # rbind tolerante a colunas diferentes entre paginas/respostas.
  partes <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, partes)
  if (!length(partes)) return(data.frame())
  colunas <- unique(unlist(lapply(partes, names)))
  partes <- lapply(partes, function(x) { for (n in setdiff(colunas, names(x))) x[[n]] <- NA; x[colunas] })
  resultado <- do.call(rbind, partes)
  rownames(resultado) <- NULL
  resultado
}

criar_cliente_api <- function(pausa, max_tentativas) {
  # O estado do limitador e compartilhado por todas as consultas, inclusive
  # tentativas repetidas e paginas seguintes.
  estado <- new.env(parent = emptyenv())
  estado$ultimo_acesso <- NULL
  estado$n_requisicoes <- 0L
  aguardar_limite <- function() {
    if (is.null(estado$ultimo_acesso)) return(invisible())
    decorrido <- as.numeric(difftime(Sys.time(), estado$ultimo_acesso, units = "secs"))
    if (is.finite(decorrido) && decorrido < pausa) Sys.sleep(pausa - decorrido)
  }
  consultar_pagina <- function(url) {
    ultimo_erro <- "resposta sem o envelope esperado (items/hasMore/offset/count)"
    for (tentativa in seq_len(max_tentativas)) {
      aguardar_limite()
      estado$ultimo_acesso <- Sys.time()
      estado$n_requisicoes <- estado$n_requisicoes + 1L
      resposta <- tryCatch({
        texto <- obter_texto_url(url, timeout = TIMEOUT_REQUISICAO, tentativas = 1L)
        Encoding(texto) <- "UTF-8"
        jsonlite::fromJSON(texto, simplifyVector = TRUE, simplifyDataFrame = TRUE, simplifyMatrix = FALSE)
      }, error = function(e) conditionMessage(e))
      if (is.list(resposta) && all(c("items", "hasMore", "offset", "count") %in% names(resposta))) return(resposta)
      if (is.character(resposta)) ultimo_erro <- resposta
      if (tentativa < max_tentativas) Sys.sleep(min(2 ^ tentativa, 8))
    }
    stop("Falha apos ", max_tentativas, " tentativa(s) em ", url, ": ", ultimo_erro, call. = FALSE)
  }
  consultar <- function(endpoint, parametros = list()) {
    # Percorre as paginas ate hasMore = false e devolve os itens empilhados.
    paginas <- list()
    offset <- 0L
    repeat {
      p <- parametros
      if (offset > 0L) p$offset <- offset
      resposta <- consultar_pagina(montar_url(endpoint, p))
      itens <- if (is.data.frame(resposta$items)) resposta$items else data.frame()
      paginas[[length(paginas) + 1L]] <- itens
      if (!isTRUE(resposta$hasMore)) break
      if (!nrow(itens)) stop("A API informou hasMore, mas devolveu pagina vazia: ", endpoint)
      offset <- as.integer(resposta$offset) + nrow(itens)
    }
    empilhar(paginas)
  }
  list(consultar = consultar, total = function() estado$n_requisicoes)
}

# ---- 2. Gravacao atomica: JSON (comprimido quando o destino termina em .gz) ---
escrever_json <- function(objeto, destino) {
  temporario <- paste0(destino, ".part")
  texto <- jsonlite::toJSON(objeto, dataframe = "rows", auto_unbox = TRUE, na = "null", null = "null", digits = NA)
  con <- if (grepl("[.]gz$", destino)) gzfile(temporario, open = "w") else file(temporario, open = "w", encoding = "UTF-8")
  writeLines(texto, con, useBytes = TRUE)
  close(con)
  if (file.exists(destino)) unlink(destino, force = TRUE)
  if (!file.rename(temporario, destino)) stop("Nao foi possivel gravar ", destino)
  invisible(destino)
}

# ---- 3. Universo de entes: esfera "M" (municipios), restrito a UFS_ATIVAS -----
cliente <- criar_cliente_api(PAUSA_SEGUNDOS, MAX_TENTATIVAS)
log_msg("Baixando o cadastro de entes.")
entes <- cliente$consultar("entes")
obrigatorias <- c("cod_ibge", "ente", "uf", "esfera")
if (!all(obrigatorias %in% names(entes))) {
  stop("Cadastro de entes sem as colunas: ", paste(setdiff(obrigatorias, names(entes)), collapse = ", "))
}
escrever_json(list(metadados = list(fonte = "STN - API de Dados Abertos do SICONFI", endpoint = "entes",
                                    coletado_em = format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
                   items = entes), file.path(dir_saida, "entes.json"))
municipios <- entes[as.character(entes$esfera) == "M" & as.character(entes$uf) %in% UFS_ATIVAS$uf, , drop = FALSE]
municipios$cod_ibge <- padronizar_codigo7(municipios$cod_ibge)
municipios <- municipios[!is.na(municipios$cod_ibge) & !duplicated(municipios$cod_ibge), , drop = FALSE]
municipios <- municipios[order(municipios$uf, municipios$cod_ibge), , drop = FALSE]
if (!nrow(municipios)) stop("Nenhum municipio encontrado para as UFs ativas.")
codigos <- municipios$cod_ibge
log_msg(length(codigos), " municipios em ", length(unique(municipios$uf)), " UF(s); DCA ",
        ANO_INICIAL, "-", ANO_FINAL, "; RREO ", ANO_INICIAL_RREO, "-", ANO_FINAL, ".")

# ---- 4. Coletores ------------------------------------------------------------
# DCA: uma unica consulta por ente-exercicio devolve todos os anexos; guardam-se
# apenas I-C, I-D e I-E (em 2013 os anexos vem sem o prefixo "DCA-").
ANEXOS_DCA <- "Anexo I-(C|D|E)$"
coletar_dca <- function(ano, codigo) {
  itens <- cliente$consultar("dca", list(an_exercicio = ano, id_ente = codigo))
  if (nrow(itens) && "anexo" %in% names(itens)) itens <- itens[grepl(ANEXOS_DCA, itens$anexo), , drop = FALSE]
  list(items = itens, metadados = list(anexos = "I-C, I-D, I-E"))
}

# RREO Anexo 06: co_tipo_demonstrativo e obrigatorio na pratica (sem ele a API
# devolve vazio). Tenta-se o RREO completo do 6o bimestre, depois o RREO
# Simplificado (municipios < 50 mil hab.) do 6o bimestre e, por fim, o 2o
# semestre da publicacao semestral simplificada (LRF, art. 63). Ausencia nas
# tres modalidades e registrada como arquivo sem itens; nunca vira zero.
TENTATIVAS_RREO <- data.frame(tipo = c("RREO", "RREO Simplificado", "RREO Simplificado"),
                              periodo = c(6L, 6L, 2L), stringsAsFactors = FALSE)
preferencia_rreo <- new.env(parent = emptyenv())   # ultima modalidade com dados, por ente
coletar_rreo <- function(ano, codigo) {
  ordem <- seq_len(nrow(TENTATIVAS_RREO))
  preferida <- preferencia_rreo[[codigo]]
  if (!is.null(preferida)) ordem <- c(preferida, setdiff(ordem, preferida))
  itens <- data.frame()
  usada <- NA_integer_
  for (i in ordem) {
    itens <- cliente$consultar("rreo", list(
      an_exercicio = ano, nr_periodo = TENTATIVAS_RREO$periodo[i],
      co_tipo_demonstrativo = TENTATIVAS_RREO$tipo[i], no_anexo = "RREO-Anexo 06",
      co_esfera = "M", id_ente = codigo
    ))
    if (TENTATIVAS_RREO$periodo[i] == 2L && nrow(itens) && "periodicidade" %in% names(itens)) {
      # o 2o periodo so representa o encerramento do exercicio se a publicacao for semestral
      itens <- itens[toupper(substr(as.character(itens$periodicidade), 1L, 1L)) == "S", , drop = FALSE]
    }
    if (nrow(itens)) { usada <- i; assign(codigo, i, envir = preferencia_rreo); break }
  }
  list(items = itens, metadados = list(
    tipo_demonstrativo = if (is.na(usada)) NA else TENTATIVAS_RREO$tipo[usada],
    nr_periodo = if (is.na(usada)) NA else TENTATIVAS_RREO$periodo[usada]
  ))
}

# ---- 5. Coleta com retomada: exercicios recentes primeiro; pula o que existe --
coletores <- list(dca = coletar_dca, rreo = coletar_rreo)
inicio <- Sys.time()
n_gravados <- 0L
n_falhas <- 0L
for (ano in rev(seq.int(ANO_INICIAL, ANO_FINAL))) {
  for (endpoint in names(coletores)) {
    if (endpoint == "rreo" && ano < ANO_INICIAL_RREO) next
    pasta <- dir_brutos(FONTE, endpoint, ano)
    destinos <- file.path(pasta, paste0(codigos, ".json.gz"))
    existentes <- file.exists(destinos)
    pendentes <- which(!existentes)
    if (RECONSULTAR_VAZIOS) {
      pendentes <- sort(union(pendentes, which(existentes & file.info(destinos)$size < TAMANHO_VAZIO)))
    }
    log_msg(toupper(endpoint), " ", ano, ": ", length(pendentes), " ente(s) a consultar; ",
            sum(existentes), " ja em disco.")
    falhas_seguidas <- 0L
    for (k in seq_along(pendentes)) {
      i <- pendentes[k]
      resultado <- tryCatch(coletores[[endpoint]](ano, codigos[i]), error = function(e) e)
      if (inherits(resultado, "error")) {
        # sem arquivo gravado, o ente volta a ser consultado na proxima execucao
        n_falhas <- n_falhas + 1L
        falhas_seguidas <- falhas_seguidas + 1L
        log_msg("Falha em ", endpoint, " ", ano, " ", codigos[i], ": ", conditionMessage(resultado))
        if (falhas_seguidas >= MAX_FALHAS_SEGUIDAS) {
          stop("Muitas falhas seguidas; a API parece indisponivel. Execute novamente mais tarde para retomar.")
        }
        next
      }
      falhas_seguidas <- 0L
      escrever_json(list(
        metadados = c(list(fonte = "STN - API de Dados Abertos do SICONFI", endpoint = endpoint,
                           exercicio = ano, cod_ibge = codigos[i],
                           coletado_em = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                           n_itens = nrow(resultado$items)), resultado$metadados),
        items = resultado$items
      ), destinos[i])
      n_gravados <- n_gravados + 1L
      if (k %% 100L == 0L || k == length(pendentes)) {
        log_msg(toupper(endpoint), " ", ano, ": ", k, "/", length(pendentes), " entes (",
                cliente$total(), " requisicoes; ",
                round(as.numeric(difftime(Sys.time(), inicio, units = "hours")), 2), " h).")
      }
    }
  }
}

registrar_execucao(FONTE, "extracao", paste0(n_gravados, " arquivos gravados, ", n_falhas,
                                             " falha(s), ", cliente$total(), " requisicoes"))
log_msg("Extracao concluida: ", n_gravados, " arquivos gravados, ", n_falhas, " falha(s). Brutos em ", dir_saida)
