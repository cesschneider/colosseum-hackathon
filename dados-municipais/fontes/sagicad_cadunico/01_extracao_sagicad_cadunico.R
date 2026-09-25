# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_sagicad_cadunico.R
# FONTE: SAGI/MDS - MISocial (Cadastro Unico: pessoas e familias cadastradas
#        por faixa de renda) + Ipeadata (populacao municipal, denominador)
# OBJETIVO: Baixar, de forma paginada, a serie municipal-mensal do Cadastro
#           Unico para todo o Brasil e preservar o CSV consolidado bruto.
# COBERTURA: Brasil, todos os municipios; ago/2012 ate o ultimo mes publicado.
# PERIODICIDADE: mensal
# ENDPOINT: https://aplicacoes.mds.gov.br/sagi/servicos/misocial/
#           (consulta tipo Solr: fl, fq, q, sort, rows, start, wt=csv)
# SAIDAS: dados/brutos/sagicad_cadunico/sagicad_cadunico_misocial_<inicio>_<fim>.csv
#         dados/brutos/sagicad_cadunico/paginas_<inicio>_<fim>/pagina_00001.csv ...
#         dados/brutos/sagicad_cadunico/ipeadata_populacao.csv
# COMO EXECUTAR: Rscript fontes/sagicad_cadunico/01_extracao_sagicad_cadunico.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "sagicad_cadunico"

URL_MISOCIAL <- "https://aplicacoes.mds.gov.br/sagi/servicos/misocial/"
# Todos os campos abaixo existem em toda a serie (ago/2012 em diante). Os campos
# com sufixo _s chegam como texto e sao convertidos no tratamento.
CAMPOS <- c("codigo_ibge", "anomes_s", "cadun_qtd_pessoas_cadastradas_i",
            "cadun_qtd_familias_cadastradas_i", "cadun_qtde_fam_sit_extrema_pobreza_s",
            "cadun_qtde_fam_sit_pobreza_s", "cadun_qtd_familias_cadastradas_pobreza_pbf_i",
            "cadun_qtd_pessoas_cadastradas_pobreza_pbf_i", "cadun_qtd_familias_cadastradas_baixa_renda_i",
            "cadun_qtd_familias_cadastradas_rfpc_ate_meio_sm_i")
FILTRO <- "cadun_qtd_pessoas_cadastradas_i:*"
LINHAS_PAGINA <- 100000L
PERIODO_INICIAL <- ano_inicial_efetivo(2012L) * 100L + 1L   # competencia aaaamm
dir_saida <- dir_brutos(FONTE)

url_misocial <- function(rows, start = 0L, ordenacao = "anomes_s asc, codigo_ibge asc") {
  paste0(URL_MISOCIAL,
         "?fl=", paste(utils::URLencode(CAMPOS, reserved = TRUE), collapse = "%2C"),
         "&fq=", utils::URLencode(FILTRO, reserved = TRUE),
         "&fq=", utils::URLencode(sprintf("anomes_s:[%d TO *]", PERIODO_INICIAL), reserved = TRUE),
         "&q=*%3A*&sort=", utils::URLencode(ordenacao, reserved = TRUE),
         "&wt=csv&rows=", as.integer(rows), "&start=", as.integer(start))
}

ler_pagina <- function(arquivo) {
  utils::read.csv(arquivo, colClasses = "character", check.names = FALSE,
                  na.strings = "", strip.white = TRUE, encoding = "UTF-8")
}

validar_pagina <- function(arquivo, linhas_minimas = 0L) {
  # Validacao minima: cabecalho esperado, competencia aaaamm valida, codigo IBGE
  # presente, valores numericos nao negativos e chave municipio-mes unica.
  x <- ler_pagina(arquivo)
  if (!identical(names(x), CAMPOS) || nrow(x) < linhas_minimas) return(FALSE)
  if (!nrow(x)) return(TRUE)
  periodo <- suppressWarnings(as.integer(x$anomes_s))
  brutos <- unlist(x[CAMPOS[-(1:2)]], use.names = FALSE)
  valores <- suppressWarnings(as.numeric(brutos))
  all(!is.na(periodo) & periodo >= PERIODO_INICIAL & periodo %% 100L %in% 1:12) &&
    all(!is.na(x$codigo_ibge) & nzchar(x$codigo_ibge)) &&
    all(!is.na(x$cadun_qtd_pessoas_cadastradas_i)) &&
    all(is.na(brutos) | (!is.na(valores) & valores >= 0)) &&
    !anyDuplicated(x[c("codigo_ibge", "anomes_s")])
}

# 1. Competencia mais recente disponivel na fonte (1 linha em ordem decrescente)
arquivo_ultima <- file.path(tempdir(), paste0(FONTE, "_ultima_competencia.csv"))
baixar_arquivo(url_misocial(rows = 1L, ordenacao = "anomes_s desc, codigo_ibge asc"), arquivo_ultima,
               reutilizar = FALSE, validador = function(f) validar_pagina(f, linhas_minimas = 1L), quiet = TRUE)
periodo_fonte <- as.integer(ler_pagina(arquivo_ultima)$anomes_s[[1L]])
log_msg("MISocial: competencia mais recente = ", periodo_fonte)

# 2. Download paginado (100 mil linhas por pagina). O consolidado e reutilizado
#    quando a competencia mais recente nao mudou; caso contrario a serie inteira
#    e rebaixada (a fonte pode revisar meses anteriores).
consolidado <- file.path(dir_saida, sprintf("%s_misocial_%d_%d.csv", FONTE, PERIODO_INICIAL, periodo_fonte))
reutilizado <- REUTILIZAR_BRUTOS && file.exists(consolidado)
if (reutilizado) {
  log_msg("Reutilizado: ", basename(consolidado))
} else {
  dir_paginas <- dir_brutos(FONTE, sprintf("paginas_%d_%d", PERIODO_INICIAL, periodo_fonte))
  paginas <- list()
  inicio <- 0L
  repeat {
    indice <- length(paginas) + 1L
    destino <- file.path(dir_paginas, sprintf("pagina_%05d.csv", indice))
    log_msg("Pagina ", indice, " (start = ", inicio, ")")
    baixar_arquivo(url_misocial(rows = LINHAS_PAGINA, start = inicio), destino, validador = validar_pagina)
    bloco <- ler_pagina(destino)
    if (!nrow(bloco)) {
      unlink(destino, force = TRUE)
      break
    }
    paginas[[indice]] <- bloco
    if (nrow(bloco) < LINHAS_PAGINA) break
    inicio <- inicio + LINHAS_PAGINA
  }
  if (!length(paginas)) stop("A MISocial devolveu uma base vazia.")
  bruto <- do.call(rbind, paginas)
  maximo <- max(as.integer(bruto$anomes_s))
  if (maximo != periodo_fonte) {
    stop("A base completa termina em ", maximo, ", mas a consulta inicial indicou ", periodo_fonte, ".")
  }
  escrever_csv(bruto, consolidado)
  log_msg("Consolidado gravado: ", basename(consolidado), " (", nrow(bruto), " linhas, ",
          length(paginas), " paginas)")
  # Versoes com competencia final anterior (mesmo inicio) ficam obsoletas.
  obsoletos <- list.files(dir_saida, pattern = sprintf("_misocial_%d_[0-9]{6}[.]csv$|^paginas_%d_", PERIODO_INICIAL, PERIODO_INICIAL),
                          full.names = TRUE)
  unlink(setdiff(obsoletos, c(consolidado, dir_paginas)), recursive = TRUE, force = TRUE)
}

# 3. Populacao municipal do Ipeadata: censos (POPTOT) e estimativas anuais
#    (ESTIMA_PO), no esquema serie/codigo_municipio/ano/valor. Rebaixada sempre
#    que a serie da MISocial e rebaixada (ou quando ainda nao existe).
arquivo_pop <- file.path(dir_saida, "ipeadata_populacao.csv")
if (reutilizado && file.exists(arquivo_pop)) {
  log_msg("Reutilizado: ", basename(arquivo_pop))
} else {
  pop <- rbind(ipeadata_municipal("POPTOT"), ipeadata_municipal("ESTIMA_PO"))
  pop <- pop[!is.na(pop$codigo_municipio) & !is.na(pop$valor), c("serie", "codigo_municipio", "ano", "valor")]
  escrever_csv(pop, arquivo_pop)
  log_msg("Populacao gravada: ", basename(arquivo_pop), " (", nrow(pop), " linhas, ",
          min(pop$ano), "-", max(pop$ano), ")")
}

registrar_execucao(FONTE, "extracao", paste0("MISocial ate ", periodo_fonte, ": ", basename(consolidado)))
