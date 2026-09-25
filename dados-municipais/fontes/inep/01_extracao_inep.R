# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_inep.R
# FONTE: Inep - Censo Escolar, Taxas de Rendimento Escolar, Ideb, Enem e Censo
#        da Educacao Superior (dados abertos)
# OBJETIVO: Descobrir nas paginas do portal gov.br/inep os arquivos oficiais de
#           cada fluxo, baixar os ZIPs para todo o Brasil e validar o schema
#           minimo (membros e colunas obrigatorias), sem transformar nada.
# COBERTURA: Brasil, todos os municipios; Censo Escolar e taxas desde 2007,
#            Ideb desde 2005 (a edicao mais recente traz a serie completa),
#            Enem e Censo Superior desde 2009, ate a edicao mais recente.
# PERIODICIDADE: anual (Ideb bienal)
# ENDPOINT: https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos
# SAIDAS: dados/brutos/inep/<fluxo>/<fluxo>[_<etapa>]_<ano>.zip
#         dados/brutos/inep/links_descobertos.csv (plano de coleta)
# COMO EXECUTAR: Rscript fontes/inep/01_extracao_inep.R
#   PAINEL_INEP_FLUXOS="ideb_municipios,taxas_rendimento"  restringe os fluxos
#   PAINEL_INEP_SOMENTE_PLANO=TRUE  so descobre e lista os links, sem baixar
#   PAINEL_ANO_INICIAL, PAINEL_REBAIXAR e PAINEL_TIMEOUT tambem sao respeitados
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "inep"

FLUXOS_VALIDOS <- c("censo_escolar", "taxas_rendimento", "ideb_municipios", "enem", "censo_superior")
PAGINAS_INEP <- c(
  censo_escolar    = "https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/censo-escolar",
  taxas_rendimento = "https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/indicadores-educacionais/taxas-de-rendimento-escolar",
  ideb_municipios  = "https://www.gov.br/inep/pt-br/areas-de-atuacao/pesquisas-estatisticas-e-indicadores/ideb/resultados",
  enem             = "https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/enem",
  censo_superior   = "https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/censo-da-educacao-superior"
)
ANO_INICIAL <- ano_inicial_efetivo(2007L)

fluxos_selecionados <- function() {
  pedido <- trimws(strsplit(Sys.getenv("PAINEL_INEP_FLUXOS", ""), ",")[[1L]])
  pedido <- pedido[nzchar(pedido)]
  if (!length(pedido)) return(FLUXOS_VALIDOS)
  desconhecidos <- setdiff(pedido, FLUXOS_VALIDOS)
  if (length(desconhecidos)) {
    stop("Fluxos desconhecidos em PAINEL_INEP_FLUXOS: ", paste(desconhecidos, collapse = ", "),
         ". Validos: ", paste(FLUXOS_VALIDOS, collapse = ", "))
  }
  pedido
}

# ---- 1. Descoberta de links nas paginas do portal ----------------------------

extrair_ano <- function(x) {
  # Maior ano 20xx presente em cada texto (NA quando nao ha).
  achados <- regmatches(x, gregexpr("(?<![0-9])20[0-9]{2}(?![0-9])", x, perl = TRUE))
  vapply(achados, function(a) if (length(a)) max(as.integer(a)) else NA_integer_, integer(1L))
}

url_absoluta <- function(href, base) {
  raiz <- sub("^(https?://[^/]+).*$", "\\1", base)
  pasta <- sub("/[^/]*$", "/", base)
  ifelse(grepl("^https?://", href), href,
         ifelse(startsWith(href, "/"), paste0(raiz, href), paste0(pasta, href)))
}

listar_ancoras <- function(url) {
  # Pares (texto, href) das ancoras da pagina. Complementa listar_links_pagina(),
  # que devolve so os hrefs: no portal do Inep o rotulo identifica o arquivo
  # ("Microdados do Enem 2023", "Municipios", "Anos Finais").
  html <- obter_texto_url(url)
  Encoding(html) <- "UTF-8"
  ancoras <- regmatches(html, gregexpr("(?s)<a\\b[^>]*href=[\"'][^\"']+[\"'][^>]*>.*?</a>", html, perl = TRUE))[[1L]]
  href <- sub("(?s)^<a\\b[^>]*href=[\"']([^\"']+)[\"'].*$", "\\1", ancoras, perl = TRUE)
  texto <- sub("(?s)^<a\\b[^>]*>(.*)</a>$", "\\1", ancoras, perl = TRUE)
  texto <- gsub("<[^>]+>", " ", texto, perl = TRUE)
  texto <- gsub("&amp;", "&", gsub("&nbsp;|&#160;", " ", texto))
  texto <- trimws(gsub("[[:space:]]+", " ", texto))
  unique(data.frame(texto = texto, href = url_absoluta(href, url), stringsAsFactors = FALSE))
}

listar_abas <- function(url) {
  # Abas dinamicas do portal: <div class="tab-content" data-id="2023" data-url="...">.
  html <- obter_texto_url(url)
  Encoding(html) <- "UTF-8"
  divs <- regmatches(html, gregexpr("<[^>]*data-url=[\"'][^\"']+[\"'][^>]*>", html, perl = TRUE))[[1L]]
  divs <- divs[grepl("tab-content", divs, fixed = TRUE)]
  data.frame(
    id = ifelse(grepl("data-id=", divs, fixed = TRUE),
                sub("^.*data-id=[\"']([^\"']*)[\"'].*$", "\\1", divs), NA_character_),
    url = url_absoluta(sub("^.*data-url=[\"']([^\"']+)[\"'].*$", "\\1", divs), url),
    stringsAsFactors = FALSE
  )
}

descobrir_microdados <- function(fluxo, padrao_texto, ano_minimo, excluir_texto = NULL) {
  # Paginas de microdados: uma ancora "Microdados do <pesquisa> <ano>" por edicao.
  pagina <- PAGINAS_INEP[[fluxo]]
  links <- listar_ancoras(pagina)
  texto <- normalizar_nome(links$texto)
  manter <- grepl(padrao_texto, texto, perl = TRUE) & grepl("[.]zip($|[?])", links$href, ignore.case = TRUE)
  if (!is.null(excluir_texto)) manter <- manter & !grepl(excluir_texto, texto, perl = TRUE)
  links <- links[manter, , drop = FALSE]
  # O ano vem do nome do arquivo, nao do rotulo: rotulos trazem tambem a data
  # de revisao ("... 2019 (Atualizado em 8/3/2023)").
  links$ano <- extrair_ano(basename(links$href))
  links <- links[!is.na(links$ano) & links$ano >= ano_minimo, , drop = FALSE]
  if (!nrow(links)) stop("Nenhum ZIP encontrado para ", fluxo, " em ", pagina)
  data.frame(fluxo = fluxo, subfluxo = NA_character_, ano = links$ano, url = links$href,
             pagina = pagina, stringsAsFactors = FALSE)
}

descobrir_taxas <- function(ano_minimo) {
  # Uma aba por ano; dentro dela, o ZIP rotulado "Municipios".
  pagina <- PAGINAS_INEP[["taxas_rendimento"]]
  abas <- listar_abas(pagina)
  # Ano por regex: ha abas rotuladas "2021." (com ponto), que as.integer perderia.
  abas$ano <- extrair_ano(paste(abas$id, basename(abas$url)))
  abas <- abas[!is.na(abas$ano) & abas$ano >= ano_minimo, , drop = FALSE]
  if (!nrow(abas)) stop("Nenhuma aba anual encontrada em ", pagina)
  itens <- lapply(seq_len(nrow(abas)), function(i) {
    links <- listar_ancoras(abas$url[i])
    manter <- grepl("^municip", normalizar_nome(links$texto)) &
      grepl("[.]zip($|[?])", links$href, ignore.case = TRUE)
    if (sum(manter) != 1L) {
      log_msg("Aviso: ", sum(manter), " ZIP(s) municipal(is) na aba ", abas$ano[i], " das taxas; aba ignorada.")
      return(NULL)
    }
    data.frame(fluxo = "taxas_rendimento", subfluxo = NA_character_, ano = abas$ano[i],
               url = links$href[manter], pagina = abas$url[i], stringsAsFactors = FALSE)
  })
  do.call(rbind, itens)
}

descobrir_ideb <- function() {
  # A pagina de resultados ja foi publicada com abas dinamicas e com paginas
  # anuais; as duas estruturas sao percorridas. Selecionam-se os tres ZIPs
  # municipais (anos iniciais, anos finais, ensino medio) da edicao mais
  # recente que possua as tres etapas; cada planilha traz a serie desde 2005.
  pagina <- PAGINAS_INEP[["ideb_municipios"]]
  indice <- listar_ancoras(pagina)
  urls <- unique(c(pagina, listar_abas(pagina)$url,
                   indice$href[grepl("/ideb/resultados/[0-9]{4}", indice$href)]))
  achados <- do.call(rbind, lapply(urls, function(u) {
    links <- tryCatch(listar_ancoras(u), error = function(e) NULL)
    if (is.null(links)) return(NULL)
    chave <- normalizar_nome(paste(links$texto, basename(links$href)))
    manter <- grepl("[.]zip($|[?])", links$href, ignore.case = TRUE) & grepl("municip", chave) &
      grepl("anos iniciais|anos finais|ensino medio", chave)
    if (!any(manter)) return(NULL)
    chave <- chave[manter]
    data.frame(
      fluxo = "ideb_municipios",
      subfluxo = ifelse(grepl("anos iniciais", chave), "anos_iniciais",
                        ifelse(grepl("anos finais", chave), "anos_finais", "ensino_medio")),
      ano = extrair_ano(basename(links$href[manter])), url = links$href[manter], pagina = u,
      stringsAsFactors = FALSE
    )
  }))
  if (is.null(achados) || !nrow(achados)) stop("Nenhum ZIP municipal do Ideb localizado a partir de ", pagina)
  achados <- achados[!is.na(achados$ano) & !duplicated(achados[c("subfluxo", "ano", "url")]), , drop = FALSE]
  etapas <- c("anos_iniciais", "anos_finais", "ensino_medio")
  completas <- Filter(function(a) all(etapas %in% achados$subfluxo[achados$ano == a]), unique(achados$ano))
  if (!length(completas)) stop("Nenhuma edicao do Ideb possui os tres ZIPs municipais.")
  selecao <- achados[achados$ano == max(completas), , drop = FALSE]
  if (anyDuplicated(selecao$subfluxo)) {
    log_msg("Aviso: mais de um link por etapa na edicao ", max(completas), " do Ideb; mantido o primeiro.")
    selecao <- selecao[!duplicated(selecao$subfluxo), , drop = FALSE]
  }
  selecao[match(etapas, selecao$subfluxo), , drop = FALSE]
}

# ---- 2. Validacao minima do schema dos ZIPs ----------------------------------

validar_zip <- function(arquivo) {
  # Validador para baixar_arquivo(): tamanho minimo e assinatura ZIP.
  if (file.info(arquivo)$size < 1000) return(FALSE)
  con <- file(arquivo, "rb")
  on.exit(close(con), add = TRUE)
  identical(readBin(con, "raw", 4L), as.raw(c(0x50, 0x4b, 0x03, 0x04)))
}

ler_cabecalho_zip <- function(zip, membro) {
  # Nomes de colunas (maiusculos) da primeira linha de um CSV dentro do ZIP,
  # lendo apenas o inicio do membro (microdados em latin1, separador variavel).
  con <- unz(zip, membro, open = "rb")
  on.exit(close(con), add = TRUE)
  bytes <- readBin(con, "raw", 1024L * 1024L)
  texto <- iconv(rawToChar(bytes[bytes != as.raw(0)]), from = "latin1", to = "UTF-8", sub = "")
  linha <- sub("^\ufeff", "", strsplit(texto, "\r\n|\n|\r")[[1L]][1L])
  seps <- c(";", ",", "|", "\t")
  contagem <- vapply(seps, function(s) lengths(regmatches(linha, gregexpr(s, linha, fixed = TRUE))), integer(1L))
  if (max(contagem) < 1L) stop("Separador nao reconhecido em ", membro)
  toupper(trimws(gsub("[\"']", "", strsplit(linha, seps[which.max(contagem)], fixed = TRUE)[[1L]])))
}

exigir_colunas <- function(colunas, grupos, descricao) {
  # Cada grupo (vetor de nomes alternativos) precisa de ao menos uma coluna presente.
  ausentes <- vapply(grupos, function(g) !any(toupper(g) %in% colunas), logical(1L))
  if (any(ausentes)) {
    stop("Schema de ", descricao, " sem coluna(s): ",
         paste(vapply(grupos[ausentes], paste, character(1L), collapse = "|"), collapse = ", "))
  }
  invisible(TRUE)
}

validar_schema <- function(arquivo, fluxo, ano) {
  membros <- listar_membros_zip(arquivo)
  membros <- membros[!grepl("/$", membros) & !grepl("dicion|leia|anexo|md5|~[$]", membros, ignore.case = TRUE)]
  achar <- function(padrao, descricao) {
    m <- membros[grepl(padrao, basename(membros), ignore.case = TRUE, perl = TRUE)]
    if (length(m) != 1L) stop("Esperado um arquivo de ", descricao, "; encontrados ", length(m))
    m
  }
  rotulo <- paste(fluxo, ano)
  switch(
    fluxo,
    censo_escolar = {
      combinado <- membros[grepl(sprintf("^microdados_ed_basica_%d[.]csv$", ano), basename(membros), ignore.case = TRUE)]
      if (length(combinado) == 1L) {
        # 2007-2024: um CSV por escola com totais de matriculas e docentes.
        exigir_colunas(ler_cabecalho_zip(arquivo, combinado),
                       list("SG_UF", "CO_MUNICIPIO", "CO_ENTIDADE", "QT_MAT_BAS", "QT_MAT_FUND",
                            "QT_MAT_MED", "QT_SALAS_UTILIZADAS", "QT_DOC_BAS"), rotulo)
      } else {
        # 2025+: tabelas separadas de escola, matricula e docente (por CO_ENTIDADE).
        exigir_colunas(ler_cabecalho_zip(arquivo, achar(sprintf("^Tabela_Escola_%d", ano), "escolas")),
                       list("SG_UF", "CO_MUNICIPIO", "CO_ENTIDADE", "QT_SALAS_UTILIZADAS"), rotulo)
        exigir_colunas(ler_cabecalho_zip(arquivo, achar(sprintf("^Tabela_Matricula_%d", ano), "matriculas")),
                       list("CO_ENTIDADE", "QT_MAT_BAS", "QT_MAT_FUND", "QT_MAT_MED"), rotulo)
        exigir_colunas(ler_cabecalho_zip(arquivo, achar(sprintf("^Tabela_Docente_%d", ano), "docentes")),
                       list("CO_ENTIDADE", "QT_DOC_BAS"), rotulo)
      }
    },
    taxas_rendimento = achar("[.]xlsx?$", "planilha municipal de taxas"),
    ideb_municipios = achar("[.]xlsx$", "planilha municipal do Ideb"),
    enem = {
      resultados <- achar(sprintf("^(MICRODADOS_ENEM|RESULTADOS)_%d[.]csv$", ano), "resultados do Enem")
      cabecalho <- ler_cabecalho_zip(arquivo, resultados)
      exigir_colunas(cabecalho, list("NU_NOTA_CN", "NU_NOTA_CH", "NU_NOTA_LC", "NU_NOTA_MT", "NU_NOTA_REDACAO"), rotulo)
      if (!"CO_MUNICIPIO_ESC" %in% cabecalho) {
        # Layout dividido (2024+): municipio da escola no arquivo de participantes.
        exigir_colunas(cabecalho, list("NU_INSCRICAO"), rotulo)
        exigir_colunas(ler_cabecalho_zip(arquivo, achar(sprintf("^PARTICIPANTES_%d[.]csv$", ano), "participantes do Enem")),
                       list("NU_INSCRICAO", "CO_MUNICIPIO_ESC"), rotulo)
      }
    },
    censo_superior = {
      ies <- achar("(^|_)IES_[0-9]{4}[.]csv$|ED_SUP_IES", "cadastro de IES")
      cursos <- achar("CURSOS?_[0-9]{4}[.]csv$", "cadastro de cursos")
      exigir_colunas(ler_cabecalho_zip(arquivo, ies),
                     list(c("CO_IES", "CODIGO_IES"), c("CO_MUNICIPIO_IES", "CO_MUNICIPIO", "CODMUNIC")), rotulo)
      exigir_colunas(ler_cabecalho_zip(arquivo, cursos),
                     list(c("CO_IES", "CODIGO_IES"),
                          c("QT_MAT_CURSO", "QT_MATRICULA", "QT_MATRICULAS", "QT_MAT", "QT_MATRICULA_CURSO")), rotulo)
    },
    stop("Fluxo sem validacao de schema: ", fluxo)
  )
  invisible(TRUE)
}

# ---- 3. Plano de coleta -------------------------------------------------------

fluxos <- fluxos_selecionados()
log_msg("Descobrindo arquivos no portal do Inep para: ", paste(fluxos, collapse = ", "))
plano <- do.call(rbind, list(
  if ("censo_escolar" %in% fluxos) descobrir_microdados("censo_escolar", "microdados do censo escolar", ANO_INICIAL),
  if ("taxas_rendimento" %in% fluxos) descobrir_taxas(ANO_INICIAL),
  if ("ideb_municipios" %in% fluxos) descobrir_ideb(),
  # As quatro provas por area existem apenas no Enem reformulado (2009+);
  # os ZIPs "Complemento ... Redacao" nao trazem notas por participante.
  if ("enem" %in% fluxos) descobrir_microdados("enem", "^microdados do enem", max(2009L, ANO_INICIAL),
                                               excluir_texto = "complemento"),
  # O Censo Superior foi reformulado em 2009 (coleta individual de alunos e docentes).
  if ("censo_superior" %in% fluxos) descobrir_microdados("censo_superior", "microdados do censo da educacao superior",
                                                         max(2009L, ANO_INICIAL))
))
plano <- plano[!duplicated(plano$url), , drop = FALSE]
plano <- plano[order(plano$fluxo, plano$subfluxo, plano$ano), , drop = FALSE]
for (f in unique(plano$fluxo)) dir_brutos(FONTE, f)
plano$arquivo <- file.path(DIR_BRUTOS, FONTE, plano$fluxo, sprintf(
  "%s%s_%d.zip", plano$fluxo, ifelse(is.na(plano$subfluxo), "", paste0("_", plano$subfluxo)), plano$ano))
rownames(plano) <- NULL
for (f in unique(plano$fluxo)) {
  anos <- plano$ano[plano$fluxo == f]
  log_msg(sprintf("  %-17s %2d arquivo(s), %d-%d", f, length(anos), min(anos), max(anos)))
}
escrever_csv(plano, file.path(dir_brutos(FONTE), "links_descobertos.csv"))

# ---- 4. Download atomico (reutiliza ZIPs validos) e validacao de schema ------

if (ler_booleano_env("PAINEL_INEP_SOMENTE_PLANO")) {
  log_msg("PAINEL_INEP_SOMENTE_PLANO=TRUE: plano gravado em links_descobertos.csv; nada foi baixado.")
} else {
  falhas <- character()
  for (i in seq_len(nrow(plano))) {
    item <- plano[i, ]
    resultado <- tryCatch({
      baixar_arquivo(item$url, item$arquivo, validador = validar_zip, tamanho_minimo = 1000L)
      validar_schema(item$arquivo, item$fluxo, item$ano)
      "ok"
    }, error = function(e) conditionMessage(e))
    if (!identical(resultado, "ok")) {
      falhas <- c(falhas, paste0(basename(item$arquivo), ": ", resultado))
      log_msg("ERRO ", basename(item$arquivo), ": ", resultado)
    }
  }
  registrar_execucao(FONTE, "extracao", paste0(nrow(plano) - length(falhas), "/", nrow(plano),
                                               " arquivos validos em ", dir_brutos(FONTE)))
  if (length(falhas)) {
    stop("Extracao concluida com ", length(falhas), " falha(s):\n", paste(falhas, collapse = "\n"))
  }
  log_msg("Extracao do Inep concluida: ", nrow(plano), " arquivo(s) em ", dir_brutos(FONTE))
}
