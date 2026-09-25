# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_inep.R
# FONTE: Inep - Censo Escolar, Taxas de Rendimento Escolar, Ideb, Enem e Censo
#        da Educacao Superior
# OBJETIVO: Ler os ZIPs preservados pelo script 01, harmonizar os layouts de
#           cada edicao e agregar os indicadores por municipio-ano em cinco
#           bases municipais (todo o Brasil), mais o dicionario de variaveis.
# ENTRADAS: dados/brutos/inep/<fluxo>/*.zip
# SAIDAS: dados/tratados/inep/inep_censo_escolar_municipal.csv
#         dados/tratados/inep/inep_rendimento_municipal.csv
#         dados/tratados/inep/inep_ideb_municipal.csv
#         dados/tratados/inep/inep_enem_municipal.csv
#         dados/tratados/inep/inep_educacao_superior_municipal.csv
#         dados/tratados/inep/inep_dicionario_variaveis.csv
#         dados/brutos/inep/parciais/<recorte>/<fluxo>_<ano>.csv (retomada)
# COMO EXECUTAR: Rscript fontes/inep/02_tratamento_inep.R
#   PAINEL_INEP_FLUXOS="ideb_municipios,taxas_rendimento" restringe os fluxos;
#   PAINEL_UFS e PAINEL_ANO_INICIAL restringem UFs e anos (testes);
#   PAINEL_INEP_REPROCESSAR=TRUE ignora as parciais ja gravadas;
#   PAINEL_INEP_TEMP=<pasta> define onde descompactar os microdados grandes
#   (o CSV do Enem chega a 4 GB por edicao).
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table", "readxl"))
library(data.table)
FONTE <- "inep"

FLUXOS_VALIDOS <- c("censo_escolar", "taxas_rendimento", "ideb_municipios", "enem", "censo_superior")
NOMES_BASES <- c(censo_escolar = "inep_censo_escolar_municipal", taxas_rendimento = "inep_rendimento_municipal",
                 ideb_municipios = "inep_ideb_municipal", enem = "inep_enem_municipal",
                 censo_superior = "inep_educacao_superior_municipal")
ANO_INICIAL <- ano_inicial_efetivo(2007L)
ANO_INICIAL_IDEB <- ano_inicial_efetivo(2005L)
REPROCESSAR <- ler_booleano_env("PAINEL_INEP_REPROCESSAR")
DIR_TEMP <- Sys.getenv("PAINEL_INEP_TEMP", unset = tempdir())
# Parciais separadas por recorte de UFs, para um teste com PAINEL_UFS nao
# contaminar a execucao nacional.
RECORTE <- if (nrow(UFS_ATIVAS) == nrow(UFS)) "brasil" else paste(sort(UFS_ATIVAS$uf), collapse = "-")
DIR_PARCIAIS <- dir_brutos(FONTE, "parciais", RECORTE)

fluxos_selecionados <- function() {
  pedido <- trimws(strsplit(Sys.getenv("PAINEL_INEP_FLUXOS", ""), ",")[[1L]])
  pedido <- pedido[nzchar(pedido)]
  if (!length(pedido)) return(FLUXOS_VALIDOS)
  desconhecidos <- setdiff(pedido, FLUXOS_VALIDOS)
  if (length(desconhecidos)) stop("Fluxos desconhecidos em PAINEL_INEP_FLUXOS: ", paste(desconhecidos, collapse = ", "))
  pedido
}

# ---- 1. Helpers ---------------------------------------------------------------

soma_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
como_numero <- function(x) if (is.numeric(x)) as.numeric(x) else para_numero(x)
contar_escolas <- function(codigo, matriculas) {
  # Escolas distintas com matricula positiva na etapa.
  if (all(is.na(matriculas))) NA_integer_ else uniqueN(codigo[!is.na(matriculas) & matriculas > 0])
}
filtrar_ufs <- function(dt) {
  # Mantem codigos validos das UFs ativas (todas as 27 por padrao).
  dt[!is.na(codigo_municipio) & substr(codigo_municipio, 1L, 2L) %in% as.character(UFS_ATIVAS$cod_uf)]
}
primeira_coluna <- function(nomes, candidatos, obrigatoria = TRUE) {
  achada <- candidatos[candidatos %in% nomes]
  if (!length(achada)) {
    if (obrigatoria) stop("Nenhuma coluna encontrada entre: ", paste(candidatos, collapse = ", "))
    return(NA_character_)
  }
  achada[[1L]]
}
ano_do_arquivo <- function(arquivo) as.integer(sub("^.*_([0-9]{4})[.]zip$", "\\1", basename(arquivo)))
listar_zips <- function(fluxo) {
  arquivos <- list.files(dir_brutos(FONTE, fluxo), pattern = "_[0-9]{4}[.]zip$", full.names = TRUE)
  arquivos[ano_do_arquivo(arquivos) >= ANO_INICIAL]
}

achar_membro <- function(zip, padrao, descricao, obrigatorio = TRUE) {
  membros <- listar_membros_zip(zip)
  membros <- membros[!grepl("/$", membros) & !grepl("dicion|leia|anexo|md5|~[$]", membros, ignore.case = TRUE)]
  m <- membros[grepl(padrao, basename(membros), ignore.case = TRUE, perl = TRUE)]
  if (length(m) == 1L) return(m)
  if (!length(m) && !obrigatorio) return(NA_character_)
  stop("Esperado um arquivo de ", descricao, " em ", basename(zip), "; encontrados ", length(m))
}

extrair_membro <- function(zip, membro, pasta) {
  # Extrai um unico membro para `pasta` e devolve seu caminho. Membros zip64
  # (mais de 4 GB descompactados, ex.: Enem 2009) podem exceder o unzip interno
  # do R; nesse caso recorre ao tar (Windows) ou unzip (Linux/macOS) do sistema.
  dir.create(pasta, recursive = TRUE, showWarnings = FALSE)
  localizar <- function() {
    a <- list.files(pasta, recursive = TRUE, full.names = TRUE)
    a <- a[toupper(basename(a)) == toupper(basename(membro))]
    if (length(a) == 1L && file.info(a)$size > 0) a else NA_character_
  }
  ok <- tryCatch({ suppressWarnings(descompactar_zip(zip, pasta, membros = membro)); TRUE }, error = function(e) FALSE)
  arquivo <- if (ok) localizar() else NA_character_
  if (is.na(arquivo)) {
    windows <- .Platform$OS.type == "windows"
    system2(if (windows) "tar" else "unzip",
            if (windows) c("-xf", shQuote(zip), "-C", shQuote(pasta), shQuote(membro))
            else c("-o", "-q", shQuote(zip), shQuote(membro), "-d", shQuote(pasta)),
            stdout = FALSE, stderr = FALSE)
    arquivo <- localizar()
    if (is.na(arquivo)) stop("Falha ao extrair ", membro, " de ", basename(zip))
  }
  arquivo
}

ler_csv_zip <- function(zip, padrao, colunas, descricao, obrigatorio = TRUE) {
  # Extrai um membro CSV para a pasta temporaria e le apenas as colunas pedidas
  # (microdados do Inep: latin1, separador ";" ou "|" detectado pelo fread).
  membro <- achar_membro(zip, padrao, descricao, obrigatorio)
  if (is.na(membro)) return(NULL)
  pasta <- tempfile("inep_", tmpdir = DIR_TEMP)
  on.exit(unlink(pasta, recursive = TRUE, force = TRUE), add = TRUE)
  arquivo <- extrair_membro(zip, membro, pasta)
  cabecalho <- names(fread(arquivo, nrows = 0L, encoding = "Latin-1", showProgress = FALSE))
  nomes <- toupper(sub(paste0("^", intToUtf8(0xFEFF)), "", cabecalho))
  presentes <- cabecalho[nomes %in% toupper(colunas)]
  if (!length(presentes)) stop("Nenhuma das colunas esperadas em ", membro)
  dados <- fread(arquivo, select = presentes, encoding = "Latin-1", showProgress = FALSE,
                 na.strings = c("", "NA", "N/A", "-", "--", "ND"))
  setnames(dados, toupper(sub(paste0("^", intToUtf8(0xFEFF)), "", names(dados))))
  dados
}

ler_planilha_zip <- function(zip, padrao, descricao) {
  # Extrai a planilha (xls/xlsx) para uma pasta temporaria; devolve caminho e pasta.
  membro <- achar_membro(zip, padrao, descricao)
  pasta <- tempfile("inep_", tmpdir = DIR_TEMP)
  list(arquivo = extrair_membro(zip, membro, pasta), pasta = pasta)
}

# ---- 2. Censo Escolar: matriculas, escolas, salas e docentes -----------------

processar_censo_escolar <- function(zip, ano) {
  campos <- c("CO_MUNICIPIO", "CO_ENTIDADE", "QT_MAT_BAS", "QT_MAT_FUND", "QT_MAT_MED", "QT_SALAS_UTILIZADAS", "QT_DOC_BAS")
  # 2007-2024: um CSV com uma linha por escola e totais de matriculas/docentes.
  escolas <- ler_csv_zip(zip, sprintf("^microdados_ed_basica_%d[.]csv$", ano), campos, "escolas", obrigatorio = FALSE)
  if (is.null(escolas)) {
    # 2025+: tabelas separadas de escola, matricula e docente, uma linha por CO_ENTIDADE.
    escolas <- ler_csv_zip(zip, sprintf("^Tabela_Escola_%d", ano), campos[1:3], "escolas")
    escolas <- escolas[, intersect(c("CO_MUNICIPIO", "CO_ENTIDADE", "QT_SALAS_UTILIZADAS"), names(escolas)), with = FALSE]
    matriculas <- ler_csv_zip(zip, sprintf("^Tabela_Matricula_%d", ano), c("CO_ENTIDADE", "QT_MAT_BAS", "QT_MAT_FUND", "QT_MAT_MED"), "matriculas")
    docentes <- ler_csv_zip(zip, sprintf("^Tabela_Docente_%d", ano), c("CO_ENTIDADE", "QT_DOC_BAS"), "docentes")
    if (anyDuplicated(matriculas$CO_ENTIDADE) || anyDuplicated(docentes$CO_ENTIDADE)) {
      stop("Tabelas de matricula/docente com mais de uma linha por escola em ", ano)
    }
    escolas <- merge(merge(escolas, matriculas, by = "CO_ENTIDADE", all.x = TRUE), docentes, by = "CO_ENTIDADE", all.x = TRUE)
  }
  escolas[, codigo_municipio := padronizar_codigo7(CO_MUNICIPIO)]
  escolas <- filtrar_ufs(escolas)
  if (anyNA(escolas$CO_ENTIDADE) || anyDuplicated(escolas$CO_ENTIDADE)) {
    stop("Censo Escolar ", ano, " sem uma linha unica por escola; a soma de docentes seria insegura")
  }
  for (v in c("QT_MAT_BAS", "QT_MAT_FUND", "QT_MAT_MED", "QT_SALAS_UTILIZADAS", "QT_DOC_BAS")) {
    if (v %in% names(escolas)) escolas[, (v) := como_numero(get(v))] else escolas[, (v) := NA_real_]
  }
  # Regra de docentes: QT_DOC_BAS e o total de docentes da educacao basica por
  # escola. A soma QT_DOC_INF + QT_DOC_FUND + QT_DOC_MED contaria o mesmo
  # docente em cada etapa e por isso nao e usada; sem QT_DOC_BAS o valor fica NA.
  if (all(is.na(escolas$QT_DOC_BAS))) log_msg("Aviso: QT_DOC_BAS ausente no Censo Escolar ", ano, "; num_professores fica NA.")
  escolas[, .(
    num_matriculas_ensino_basico = soma_na(QT_MAT_BAS),
    num_matriculas_ensino_fundamental = soma_na(QT_MAT_FUND),
    num_matriculas_ensino_medio = soma_na(QT_MAT_MED),
    num_escolas_ensino_basico = contar_escolas(CO_ENTIDADE, QT_MAT_BAS),
    num_escolas_ensino_fundamental = contar_escolas(CO_ENTIDADE, QT_MAT_FUND),
    num_escolas_ensino_medio = contar_escolas(CO_ENTIDADE, QT_MAT_MED),
    num_salas_aula = soma_na(QT_SALAS_UTILIZADAS),
    num_professores = soma_na(QT_DOC_BAS)
  ), by = codigo_municipio]
}

# ---- 3. Taxas de rendimento: aprovacao, reprovacao e abandono ----------------

# Layout recente: nomes de campo na planilha (1 = aprovacao, 2 = reprovacao,
# 3 = abandono; FUN = fundamental, MED = medio; sem sufixo = total da etapa).
COLUNAS_TAXAS <- c(
  taxa_aprovacao_ensino_fundamental = "1_CAT_FUN", taxa_aprovacao_ensino_medio = "1_CAT_MED",
  taxa_reprovacao_ensino_fundamental = "2_CAT_FUN", taxa_reprovacao_ensino_medio = "2_CAT_MED",
  taxa_abandono_ensino_fundamental = "3_CAT_FUN", taxa_abandono_ensino_medio = "3_CAT_MED"
)

padroes_taxa <- function(taxa, etapa) {
  # Layout historico: nome completo do total da etapa (celula isolada ou nome
  # hierarquico das linhas de cabecalho), nunca posicao. Rotulos normalizados
  # sem acento/pontuacao, ex.: "total reprovacao no ens fundamental".
  if (etapa == "fund") {
    c(sprintf("^total %s (no )?(ens|ensino) fundamental( de 8 e 9 anos)?$", taxa),
      sprintf("^total %s fundamental$", taxa),
      sprintf("^taxa de %s ensino fundamental de 8 e 9 anos total$", taxa))
  } else {
    c(sprintf("^total %s (no )?(ens|ensino) medio$", taxa),
      sprintf("^total %s medio$", taxa),
      sprintf("^taxa de %s ensino medio total$", taxa))
  }
}

localizar_coluna <- function(cabecalho, hierarquico, padroes, descricao) {
  achadas <- which(vapply(seq_len(ncol(cabecalho)), function(j) {
    any(vapply(padroes, function(p) {
      any(grepl(p, cabecalho[, j], perl = TRUE)) || grepl(p, hierarquico[j], perl = TRUE)
    }, logical(1L)))
  }, logical(1L)))
  if (length(achadas) != 1L) stop("Esperada uma coluna de ", descricao, "; encontradas ", length(achadas))
  achadas
}

ler_aba_taxas <- function(planilha, aba, ano) {
  m <- as.matrix(readxl::read_excel(planilha, sheet = aba, col_names = FALSE, col_types = "text", .name_repair = "minimal"))
  if (!nrow(m)) return(NULL)
  m[is.na(m)] <- ""
  m[] <- trimws(m)
  linha_maquina <- which(apply(m, 1L, function(x) any(x == "CO_MUNICIPIO")))[1L]
  if (!is.na(linha_maquina)) {
    nomes <- toupper(m[linha_maquina, ])
    dados <- m[-seq_len(linha_maquina), , drop = FALSE]
    pegar <- function(opcoes) {
      j <- which(nomes %in% opcoes)[1L]
      if (is.na(j)) stop("Campo ausente na planilha de taxas ", ano, ": ", opcoes[[1L]])
      dados[, j]
    }
    bloco <- data.table(codigo = pegar("CO_MUNICIPIO"), localizacao = pegar(c("NO_CATEGORIA", "NO_LOCALIZACAO")),
                        rede = pegar(c("NO_DEPENDENCIA", "NO_REDE", "DEPENDENCIA")))
    for (v in names(COLUNAS_TAXAS)) bloco[, (v) := pegar(COLUNAS_TAXAS[[v]])]
    return(bloco)
  }
  # Layout historico: cabecalho descritivo em varias linhas com celulas mescladas.
  norm <- m
  norm[] <- normalizar_nome(m)
  linha_rotulo <- which(apply(norm, 1L, function(x) any(grepl("^codigo (do )?municipio$", x))))[1L]
  if (is.na(linha_rotulo)) {
    log_msg("Aviso: aba '", aba, "' das taxas ", ano, " sem cabecalho reconhecido; ignorada.")
    return(NULL)
  }
  col_codigo <- which(grepl("^codigo (do )?municipio$", norm[linha_rotulo, ]))[1L]
  linha_dados <- which(seq_len(nrow(m)) > linha_rotulo & grepl("^[0-9]{7}$", m[, col_codigo]))[1L]
  if (is.na(linha_dados)) return(NULL)
  cabecalho <- norm[linha_rotulo:(linha_dados - 1L), , drop = FALSE]
  propagado <- cabecalho
  for (i in seq_len(nrow(propagado))) {
    for (j in seq_len(ncol(propagado))[-1L]) if (!nzchar(propagado[i, j])) propagado[i, j] <- propagado[i, j - 1L]
  }
  hierarquico <- apply(propagado, 2L, function(x) paste(unique(x[nzchar(x)]), collapse = " "))
  dados <- m[linha_dados:nrow(m), , drop = FALSE]
  bloco <- data.table(
    codigo = dados[, col_codigo],
    localizacao = dados[, localizar_coluna(cabecalho, hierarquico, "^localizacao$", "localizacao")],
    rede = dados[, localizar_coluna(cabecalho, hierarquico, c("^rede$", "^dependencia administrativa$"), "rede")]
  )
  for (v in names(COLUNAS_TAXAS)) {
    taxa <- sub("^taxa_([a-z]+)_.*$", "\\1", v)
    etapa <- if (grepl("fundamental$", v)) "fund" else "med"
    bloco[, (v) := dados[, localizar_coluna(cabecalho, hierarquico, padroes_taxa(taxa, etapa), v)]]
  }
  bloco
}

processar_taxas <- function(zip, ano) {
  planilha <- ler_planilha_zip(zip, "[.]xlsx?$", "planilha municipal de taxas")
  on.exit(unlink(planilha$pasta, recursive = TRUE, force = TRUE), add = TRUE)
  # Planilhas antigas podem ter uma aba por regiao: todas sao empilhadas.
  blocos <- lapply(readxl::excel_sheets(planilha$arquivo), function(aba) ler_aba_taxas(planilha$arquivo, aba, ano))
  taxas <- rbindlist(Filter(Negate(is.null), blocos), use.names = TRUE)
  if (!nrow(taxas)) stop("Nenhuma linha reconhecida na planilha de taxas de ", ano)
  taxas[, codigo_municipio := padronizar_codigo7(codigo)]
  # Linha municipal total: localizacao Total (urbana + rural) e rede Total.
  taxas <- filtrar_ufs(taxas)[normalizar_nome(localizacao) == "total" & normalizar_nome(rede) %in% c("total", "total geral")]
  for (v in names(COLUNAS_TAXAS)) taxas[, (v) := para_numero(get(v))]
  # O Inep publica as taxas em pontos percentuais (0-100). Se a planilha guardar
  # fracoes (0-1), a aprovacao maxima fica abaixo de 1 e a escala e corrigida.
  if (isTRUE(max(taxas$taxa_aprovacao_ensino_fundamental, na.rm = TRUE) <= 1)) {
    for (v in names(COLUNAS_TAXAS)) taxas[, (v) := get(v) * 100]
  }
  fora <- vapply(names(COLUNAS_TAXAS), function(v) any(!is.na(taxas[[v]]) & (taxas[[v]] < 0 | taxas[[v]] > 100)), logical(1L))
  if (any(fora)) stop("Taxa fora de [0, 100] em ", ano, ": ", paste(names(COLUNAS_TAXAS)[fora], collapse = ", "))
  if (anyDuplicated(taxas$codigo_municipio)) stop("Chave municipal duplicada nas taxas de ", ano)
  taxas[, c("codigo_municipio", names(COLUNAS_TAXAS)), with = FALSE]
}

# ---- 4. Ideb: rede publica por etapa (serie completa na edicao mais recente) --

processar_ideb <- function(zips) {
  etapas <- c("anos_iniciais", "anos_finais", "ensino_medio")
  longos <- lapply(zips, function(zip) {
    etapa <- sub("^ideb_municipios_(.*)_[0-9]{4}[.]zip$", "\\1", basename(zip))
    planilha <- ler_planilha_zip(zip, "[.]xlsx$", "planilha municipal do Ideb")
    on.exit(unlink(planilha$pasta, recursive = TRUE, force = TRUE), add = TRUE)
    aba <- readxl::excel_sheets(planilha$arquivo)[[1L]]
    amostra <- as.matrix(readxl::read_excel(planilha$arquivo, sheet = aba, col_names = FALSE, col_types = "text",
                                            n_max = 30L, .name_repair = "minimal"))
    linha_nomes <- which(apply(amostra, 1L, function(x) any(!is.na(x) & trimws(x) == "CO_MUNICIPIO")))[1L]
    if (is.na(linha_nomes)) stop("Cabecalho do Ideb nao reconhecido em ", basename(zip))
    dados <- as.data.table(readxl::read_excel(planilha$arquivo, sheet = aba, skip = linha_nomes - 1L,
                                              col_types = "text", .name_repair = "minimal"))
    setnames(dados, toupper(trimws(names(dados))))
    col_rede <- primeira_coluna(names(dados), c("REDE", "NO_REDE", "NO_DEPENDENCIA"))
    notas <- grep("^VL_OBSERVADO_[0-9]{4}$", names(dados), value = TRUE)
    notas <- notas[as.integer(sub(".*_", "", notas)) >= ANO_INICIAL_IDEB]
    if (!length(notas)) stop("Planilha do Ideb sem colunas VL_OBSERVADO_<ano>: ", basename(zip))
    # Resultado da rede publica (estadual + municipal), como divulgado pelo Inep.
    dados <- dados[normalizar_nome(get(col_rede)) == "publica"]
    dados[, codigo_municipio := padronizar_codigo7(CO_MUNICIPIO)]
    longo <- melt(filtrar_ufs(dados)[, c("codigo_municipio", notas), with = FALSE], id.vars = "codigo_municipio",
                  variable.name = "campo", value.name = "ideb", variable.factor = FALSE)
    longo[, `:=`(ano = as.integer(sub(".*_", "", campo)), ideb = para_numero(ideb), etapa = etapa)]
    longo[!is.na(ideb), .(codigo_municipio, ano, etapa, ideb)]
  })
  combinado <- rbindlist(longos)
  if (anyDuplicated(combinado[, .(codigo_municipio, ano, etapa)])) stop("Ideb municipal com chave duplicada.")
  largo <- dcast(combinado, codigo_municipio + ano ~ etapa, value.var = "ideb")
  for (e in etapas) if (!e %in% names(largo)) largo[, (e) := NA_real_]
  setnames(largo, etapas, paste0("ideb_nota_", etapas))
  largo[, c("codigo_municipio", "ano", paste0("ideb_nota_", etapas)), with = FALSE]
}

# ---- 5. Enem: notas medias por municipio da escola ----------------------------

processar_enem <- function(zip, ano) {
  notas <- c("NU_NOTA_CN", "NU_NOTA_CH", "NU_NOTA_LC", "NU_NOTA_MT", "NU_NOTA_REDACAO")
  # Ate 2023 um unico CSV (MICRODADOS_ENEM_AAAA); a partir de 2024 o pacote foi
  # dividido em RESULTADOS (notas) e PARTICIPANTES (escola e municipio).
  dados <- ler_csv_zip(zip, sprintf("^(MICRODADOS_ENEM|RESULTADOS)_%d[.]csv$", ano),
                       c("NU_INSCRICAO", "CO_MUNICIPIO_ESC", notas), "resultados do Enem")
  if (!"CO_MUNICIPIO_ESC" %in% names(dados)) {
    participantes <- ler_csv_zip(zip, sprintf("^PARTICIPANTES_%d[.]csv$", ano), c("NU_INSCRICAO", "CO_MUNICIPIO_ESC"),
                                 "participantes do Enem")
    dados <- merge(dados, participantes, by = "NU_INSCRICAO")
  }
  faltantes <- setdiff(c("CO_MUNICIPIO_ESC", notas), names(dados))
  if (length(faltantes)) stop("Enem ", ano, " sem colunas: ", paste(faltantes, collapse = ", "))
  dados[, codigo_municipio := padronizar_codigo7(CO_MUNICIPIO_ESC)]
  dados <- filtrar_ufs(dados)
  for (v in notas) dados[, (v) := como_numero(get(v))]
  # Somente participantes com as cinco notas (presentes nos dois dias, redacao
  # corrigida) e municipio da escola informado (concluintes do ensino medio).
  dados <- dados[complete.cases(dados[, notas, with = FALSE])]
  dados[, nota_media := rowMeans(as.matrix(.SD)), .SDcols = notas]
  dados[, .(
    enem_num_individuos_prova_completa = .N,
    enem_nota_ciencias_natureza = mean(NU_NOTA_CN),
    enem_nota_ciencias_humanas = mean(NU_NOTA_CH),
    enem_nota_linguagens = mean(NU_NOTA_LC),
    enem_nota_matematica = mean(NU_NOTA_MT),
    enem_nota_redacao = mean(NU_NOTA_REDACAO),
    enem_nota_media = mean(nota_media)
  ), by = codigo_municipio]
}

# ---- 6. Censo da Educacao Superior: IES, docentes e matriculas ---------------

processar_censo_superior <- function(zip, ano) {
  ies <- ler_csv_zip(zip, "(^|_)IES_[0-9]{4}[.]csv$|ED_SUP_IES",
                     c("CO_IES", "CODIGO_IES", "CO_MUNICIPIO_IES", "CO_MUNICIPIO", "CODMUNIC",
                       "QT_DOC_EXE", "QT_DOCENTE_EXE", "QT_DOCENTE_TOTAL", "QT_DOC_TOTAL"), "cadastro de IES")
  col_ies <- primeira_coluna(names(ies), c("CO_IES", "CODIGO_IES"))
  col_mun <- primeira_coluna(names(ies), c("CO_MUNICIPIO_IES", "CO_MUNICIPIO", "CODMUNIC"))
  # Docentes em exercicio informados pela IES (QT_DOC_EXE; em 2009 o campo se
  # chama QT_DOCENTE_EXE); o total geral so entra na falta desses.
  col_doc <- primeira_coluna(names(ies), c("QT_DOC_EXE", "QT_DOCENTE_EXE", "QT_DOCENTE_TOTAL", "QT_DOC_TOTAL"), obrigatoria = FALSE)
  if (is.na(col_doc)) log_msg("Aviso: sem total de docentes por IES em ", ano, "; ens_superior_num_docentes fica NA.")
  ies <- ies[, .(codigo_ies = as.character(get(col_ies)),
                 codigo_municipio = padronizar_codigo7(get(col_mun)),
                 docentes = if (is.na(col_doc)) NA_real_ else como_numero(get(col_doc)))]
  ies <- filtrar_ufs(ies)[!is.na(codigo_ies) & nzchar(codigo_ies)]
  if (anyDuplicated(ies$codigo_ies)) stop("Cadastro de IES de ", ano, " sem chave unica por instituicao.")
  instituicoes <- ies[, .(ens_superior_num_instituicoes = uniqueN(codigo_ies),
                          ens_superior_num_docentes = soma_na(docentes)), by = codigo_municipio]

  cursos <- ler_csv_zip(zip, "CURSOS?_[0-9]{4}[.]csv$",
                        c("CO_IES", "CODIGO_IES", "QT_MAT_CURSO", "QT_MATRICULA", "QT_MATRICULAS", "QT_MAT",
                          "QT_MATRICULA_CURSO", "CO_MUNICIPIO", "CO_MUNICIPIO_CURSO", "CODMUNIC_CURSO"), "cadastro de cursos")
  col_ies_curso <- primeira_coluna(names(cursos), c("CO_IES", "CODIGO_IES"))
  col_mat <- primeira_coluna(names(cursos), c("QT_MAT_CURSO", "QT_MATRICULA", "QT_MATRICULAS", "QT_MAT", "QT_MATRICULA_CURSO"))
  col_mun_curso <- primeira_coluna(names(cursos), c("CO_MUNICIPIO", "CO_MUNICIPIO_CURSO", "CODMUNIC_CURSO"), obrigatoria = FALSE)
  cursos <- cursos[, .(codigo_ies = as.character(get(col_ies_curso)),
                       matriculas = como_numero(get(col_mat)),
                       codigo_municipio = if (is.na(col_mun_curso)) NA_character_ else padronizar_codigo7(get(col_mun_curso)))]
  # Municipio do curso quando informado; senao, municipio-sede da IES.
  if (is.na(col_mun_curso)) cursos[, codigo_municipio := ies$codigo_municipio[match(codigo_ies, ies$codigo_ies)]]
  matriculas <- filtrar_ufs(cursos)[, .(ens_superior_num_matriculas = soma_na(matriculas)), by = codigo_municipio]
  merge(instituicoes, matriculas, by = "codigo_municipio", all = TRUE)
}

# ---- 7. Execucao: uma edicao por vez, com parciais para retomada --------------

processar_fluxo <- function(fluxo, zips, funcao) {
  parciais <- lapply(zips, function(zip) {
    ano <- ano_do_arquivo(zip)
    destino <- file.path(DIR_PARCIAIS, sub("[.]zip$", ".csv", basename(zip)))
    if (!REPROCESSAR && file.exists(destino)) {
      log_msg("[", fluxo, "] parcial reutilizada: ", basename(destino))
      return(as.data.table(ler_csv(destino)))
    }
    log_msg("[", fluxo, "] processando ", basename(zip))
    dados <- as.data.table(funcao(zip, ano))
    dados[, ano := ano]
    escrever_csv(dados, destino)
    invisible(gc())
    dados
  })
  rbindlist(parciais, use.names = TRUE, fill = TRUE)
}

fluxos <- fluxos_selecionados()
dicionario <- carregar_dicionario_municipios()
bases <- list()
for (fluxo in setdiff(fluxos, "ideb_municipios")) {
  zips <- listar_zips(fluxo)
  if (!length(zips)) {
    log_msg("Aviso: nenhum ZIP em ", dir_brutos(FONTE, fluxo), " (execute o script 01); fluxo ignorado.")
    next
  }
  funcao <- switch(fluxo, censo_escolar = processar_censo_escolar, taxas_rendimento = processar_taxas,
                   enem = processar_enem, censo_superior = processar_censo_superior)
  bases[[fluxo]] <- processar_fluxo(fluxo, zips, funcao)
}
if ("ideb_municipios" %in% fluxos) {
  zips <- list.files(dir_brutos(FONTE, "ideb_municipios"), pattern = "_[0-9]{4}[.]zip$", full.names = TRUE)
  if (!length(zips)) {
    log_msg("Aviso: nenhum ZIP do Ideb (execute o script 01); fluxo ignorado.")
  } else {
    # A edicao mais recente contem VL_OBSERVADO de todas as edicoes desde 2005.
    edicao <- max(ano_do_arquivo(zips))
    destino <- file.path(DIR_PARCIAIS, sprintf("ideb_municipios_%d.csv", edicao))
    bases$ideb_municipios <- if (!REPROCESSAR && file.exists(destino)) {
      log_msg("[ideb_municipios] parcial reutilizada: ", basename(destino))
      as.data.table(ler_csv(destino))
    } else {
      log_msg("[ideb_municipios] processando a edicao ", edicao)
      ideb <- processar_ideb(zips[ano_do_arquivo(zips) == edicao])
      escrever_csv(ideb, destino)
      ideb
    }
  }
}

# ---- 8. Gravacao das bases e do dicionario ------------------------------------

for (fluxo in names(bases)) {
  base <- bases[[fluxo]]
  if (is.null(base) || !nrow(base)) next
  base <- juntar_dicionario(base, dicionario)
  salvar_base_tratada(FONTE, base, nome = NOMES_BASES[[fluxo]])
}

variaveis <- list(
  censo_escolar = list(
    c("num_matriculas_ensino_basico", "Matriculas na educacao basica (soma de QT_MAT_BAS das escolas do municipio)", "matriculas"),
    c("num_matriculas_ensino_fundamental", "Matriculas no ensino fundamental (soma de QT_MAT_FUND)", "matriculas"),
    c("num_matriculas_ensino_medio", "Matriculas no ensino medio (soma de QT_MAT_MED)", "matriculas"),
    c("num_escolas_ensino_basico", "Escolas com matricula na educacao basica (QT_MAT_BAS > 0)", "escolas"),
    c("num_escolas_ensino_fundamental", "Escolas com matricula no ensino fundamental (QT_MAT_FUND > 0)", "escolas"),
    c("num_escolas_ensino_medio", "Escolas com matricula no ensino medio (QT_MAT_MED > 0)", "escolas"),
    c("num_salas_aula", "Salas de aula utilizadas (soma de QT_SALAS_UTILIZADAS)", "salas"),
    c("num_professores", "Docentes da educacao basica: soma de QT_DOC_BAS por escola (sem somar etapas; um docente em duas escolas conta duas vezes)", "docentes")
  ),
  taxas_rendimento = list(
    c("taxa_aprovacao_ensino_fundamental", "Taxa de aprovacao no ensino fundamental, total do municipio (todas as redes e localizacoes)", "% (0-100)"),
    c("taxa_aprovacao_ensino_medio", "Taxa de aprovacao no ensino medio, total do municipio", "% (0-100)"),
    c("taxa_reprovacao_ensino_fundamental", "Taxa de reprovacao no ensino fundamental, total do municipio", "% (0-100)"),
    c("taxa_reprovacao_ensino_medio", "Taxa de reprovacao no ensino medio, total do municipio", "% (0-100)"),
    c("taxa_abandono_ensino_fundamental", "Taxa de abandono no ensino fundamental, total do municipio", "% (0-100)"),
    c("taxa_abandono_ensino_medio", "Taxa de abandono no ensino medio, total do municipio", "% (0-100)")
  ),
  ideb_municipios = list(
    c("ideb_nota_anos_iniciais", "Ideb observado da rede publica, anos iniciais do ensino fundamental", "nota (0-10)"),
    c("ideb_nota_anos_finais", "Ideb observado da rede publica, anos finais do ensino fundamental", "nota (0-10)"),
    c("ideb_nota_ensino_medio", "Ideb observado da rede publica, ensino medio", "nota (0-10)")
  ),
  enem = list(
    c("enem_num_individuos_prova_completa", "Participantes com as cinco notas e escola no municipio", "participantes"),
    c("enem_nota_ciencias_natureza", "Nota media em ciencias da natureza (participantes com prova completa; municipio da escola)", "pontos (0-1000)"),
    c("enem_nota_ciencias_humanas", "Nota media em ciencias humanas", "pontos (0-1000)"),
    c("enem_nota_linguagens", "Nota media em linguagens e codigos", "pontos (0-1000)"),
    c("enem_nota_matematica", "Nota media em matematica", "pontos (0-1000)"),
    c("enem_nota_redacao", "Nota media da redacao", "pontos (0-1000)"),
    c("enem_nota_media", "Media simples das cinco notas por participante, agregada por municipio", "pontos (0-1000)")
  ),
  censo_superior = list(
    c("ens_superior_num_instituicoes", "Instituicoes de educacao superior com sede no municipio", "instituicoes"),
    c("ens_superior_num_docentes", "Docentes em exercicio informados pelas IES sediadas no municipio (QT_DOC_EXE)", "docentes"),
    c("ens_superior_num_matriculas", "Matriculas em cursos de graduacao pelo municipio do curso (ou da sede da IES)", "matriculas")
  )
)
dicionario_variaveis <- rbindlist(lapply(names(variaveis), function(fluxo) {
  rbindlist(lapply(variaveis[[fluxo]], function(v) data.table(
    variavel = v[[1L]], descricao = v[[2L]], unidade = v[[3L]],
    periodicidade = if (fluxo == "ideb_municipios") "bienal" else "anual",
    tabela = NOMES_BASES[[fluxo]],
    fonte_url = switch(fluxo,
      censo_escolar = "https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/censo-escolar",
      taxas_rendimento = "https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/indicadores-educacionais/taxas-de-rendimento-escolar",
      ideb_municipios = "https://www.gov.br/inep/pt-br/areas-de-atuacao/pesquisas-estatisticas-e-indicadores/ideb/resultados",
      enem = "https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/enem",
      censo_superior = "https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/censo-da-educacao-superior")
  )))
}))
salvar_dicionario_variaveis(FONTE, dicionario_variaveis)
log_msg("Tratamento do Inep concluido: ", length(bases), " base(s) gravada(s) em ", dir_tratados(FONTE))
