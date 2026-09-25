# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_snis_sinisa.R
# FONTE: Ministerio das Cidades - SNIS (serie historica 2000-2022) e SINISA
#        (ano de referencia 2023 em diante): agua, esgoto e qualidade dos servicos
# OBJETIVO: Ler as exportacoes da Serie Historica do SNIS e as planilhas da Base
#           Municipal do SINISA, padronizar codigos, unir as duas origens nos
#           codigos historicos do SNIS, calcular os indicadores derivados e
#           gravar a base municipal no esquema do painel.
# ENTRADAS: dados/brutos/snis_sinisa/serie_historica/*.csv (exportacoes manuais)
#           dados/brutos/snis_sinisa/sinisa/<ano>/*_Base Municipal_*.xlsx
# SAIDAS: dados/tratados/snis_sinisa/snis_sinisa_municipal.csv
#         dados/tratados/snis_sinisa/snis_sinisa_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/snis_sinisa/02_tratamento_snis_sinisa.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table", "readxl"))
library(data.table)
FONTE <- "snis_sinisa"

ANO_INICIAL <- ano_inicial_efetivo(2000L)
dicionario <- carregar_dicionario_municipios()

# Codigos historicos do SNIS (Serie Historica) e nomes das colunas da base.
NOMES <- c(
  G06A = "populacao_urbana_residente_agua", G12A = "populacao_total_residente_agua",
  AG001 = "populacao_total_atendida_agua", AG003 = "economias_ativas_agua",
  AG006 = "volume_agua_produzido_mil_m3", AG007 = "volume_agua_tratada_etas_mil_m3",
  AG015 = "volume_agua_tratada_desinfeccao_mil_m3",
  G06B = "populacao_urbana_residente_esgoto", G12B = "populacao_total_residente_esgoto",
  ES001 = "populacao_total_atendida_esgoto", ES005 = "volume_esgoto_coletado_mil_m3",
  ES006 = "volume_esgoto_tratado_mil_m3", ES008 = "economias_ativas_esgoto",
  QD002 = "numero_paralisacoes_agua", QD003 = "duracao_paralisacoes_horas",
  QD004 = "economias_atingidas_paralisacoes", QD007 = "amostras_cloro_residual_fora_padrao",
  QD009 = "amostras_turbidez_fora_padrao", QD015 = "economias_atingidas_interrupcoes_sistematicas",
  QD027 = "amostras_coliformes_totais_fora_padrao"
)
CODIGOS <- names(NOMES)
# Correspondencia SINISA -> SNIS pela descricao oficial das informacoes. Com
# mais de um codigo, o valor e a soma (urbano + rural). QD003, QD007, QD009 e
# QD027 nao possuem equivalente na Base Municipal do SINISA e ficam NA em 2023+.
MAPA_SINISA <- list(
  agua = list(G12A = "DFE0001", G06A = "DFE0002", AG001 = c("GTA0001", "GTA0002"),
              AG003 = c("GTA0008", "GTA0015"), AG006 = "GTA1001", AG007 = "GTA1002",
              AG015 = "GTA1003", QD002 = "GTA3001", QD004 = "GTA3002", QD015 = "GTA3005"),
  esgoto = list(G12B = "DFE0001", G06B = "DFE0002", ES001 = c("GTE0001", "GTE0002"),
                ES005 = "GTE1002", ES006 = "GTE1014", ES008 = c("GTE0006", "GTE0016"))
)

nome_col <- function(x) gsub("^_+|_+$", "", gsub("[^a-z0-9]+", "_", tolower(remover_acentos(as.character(x)))))
soma_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
somar_parcelas <- function(lista) {
  # Soma elemento a elemento preservando NA quando todas as parcelas sao NA.
  Reduce(function(a, b) fifelse(is.na(a) & is.na(b), NA_real_, fcoalesce(a, 0) + fcoalesce(b, 0)), lista)
}
numero_ptbr <- function(x) {
  # Exportacao da Serie Historica: ponto de milhar e virgula decimal.
  if (is.numeric(x)) return(as.numeric(x))
  x <- gsub("\u00a0", "", trimws(as.character(x)), fixed = TRUE)
  x[x %in% c("", "-", "---", "X", "x", "..", "...", "NA")] <- NA_character_
  suppressWarnings(as.numeric(gsub(",", ".", gsub(".", "", x, fixed = TRUE), fixed = TRUE)))
}
vazio <- function() data.table(codigo_municipio = character(), ano = integer(),
                               codigo_variavel = character(), valor = numeric())

# ---- 1. Serie Historica SNIS (2000-2022): exportacoes manuais ----------------
ler_exportacao_snis <- function(arquivo) {
  # A exportacao "Consolidado por Municipio" vem em UTF-16LE (BOM) com separador
  # ";". Armadilhas preservadas: o cabecalho traz "Codigo do IBGE" a mais; as
  # linhas de dados trazem uma primeira coluna tecnica sem cabecalho e um
  # delimitador final. Ler cabecalho e dados separadamente evita deslocar todas
  # as variaveis em uma coluna.
  bom <- readBin(arquivo, "raw", 2L)
  codificacao <- if (identical(bom, as.raw(c(0xFF, 0xFE)))) "UTF-16LE" else "UTF-8"
  cabecalho <- names(utils::read.table(arquivo, header = TRUE, nrows = 0L, sep = ";", quote = "\"",
                                       fileEncoding = codificacao, check.names = FALSE, comment.char = ""))
  if (identical(nome_col(cabecalho[1L]), "codigo_do_ibge")) cabecalho <- cabecalho[-1L]
  dados <- utils::read.table(arquivo, header = FALSE, skip = 1L, sep = ";", quote = "", fill = TRUE,
                             comment.char = "", fileEncoding = codificacao, colClasses = "character",
                             stringsAsFactors = FALSE)
  if (ncol(dados) == length(cabecalho) + 2L) dados <- dados[-1L]
  if (ncol(dados) == length(cabecalho) + 1L) dados <- dados[seq_along(cabecalho)]
  if (ncol(dados) != length(cabecalho)) {
    stop("Colunas inesperadas em ", basename(arquivo), ": cabecalho ", length(cabecalho), ", dados ", ncol(dados))
  }
  nomes <- nome_col(cabecalho)
  col_codigo <- which(nomes %in% c("codigo_do_municipio", "codigo_municipio", "codigo_ibge", "cod_ibge"))[1L]
  col_ano <- which(nomes %in% c("ano_de_referencia", "ano_referencia", "ano"))[1L]
  if (is.na(col_codigo) || is.na(col_ano)) stop("Colunas de codigo do municipio/ano nao encontradas em ", basename(arquivo))
  # O SNIS usa codigo IBGE de 6 digitos (sem verificador); 7 digitos tambem e aceito.
  codigo <- gsub("[^0-9]", "", dados[[col_codigo]])
  codigo7 <- rep(NA_character_, length(codigo))
  seis <- !is.na(codigo) & nchar(codigo) == 6L
  sete <- !is.na(codigo) & nchar(codigo) == 7L
  codigo7[seis] <- codigo6_para_7(codigo[seis], dicionario)
  codigo7[sete] <- padronizar_codigo7(codigo[sete])
  ano <- suppressWarnings(as.integer(dados[[col_ano]]))
  manter <- !is.na(codigo7) & !is.na(ano)
  blocos <- lapply(CODIGOS, function(cod) {
    coluna <- grep(paste0("^", cod, "([ _-]|$)"), cabecalho, ignore.case = TRUE)
    if (!length(coluna)) return(NULL)
    data.table(codigo_municipio = codigo7[manter], ano = ano[manter], codigo_variavel = cod,
               valor = numero_ptbr(dados[[coluna[1L]]][manter]))
  })
  saida <- rbindlist(blocos)
  if (!nrow(saida)) stop("Nenhuma das variaveis do painel foi encontrada em ", basename(arquivo))
  saida
}
arquivos_snis <- list.files(dir_brutos(FONTE, "serie_historica"), pattern = "[.](csv|txt)$",
                            ignore.case = TRUE, full.names = TRUE)
longo_snis <- if (length(arquivos_snis)) {
  rbindlist(lapply(arquivos_snis, function(a) {
    log_msg("Lendo exportacao da Serie Historica SNIS: ", basename(a))
    ler_exportacao_snis(a)
  }))
} else {
  log_msg("Aviso: sem exportacoes da Serie Historica SNIS; a base cobre apenas o SINISA (2023+). Veja o README.")
  vazio()
}
if (nrow(longo_snis)) longo_snis[, origem := "SNIS"]

# ---- 2. SINISA (2023+): planilhas da Base Municipal -------------------------
localizar_cabecalho <- function(arquivo, aba) {
  # As planilhas trazem linhas de titulo antes do cabecalho. A linha dos codigos
  # (cod_IBGE, DFE0001, GTA0001...) e a que mais pontua.
  previa <- suppressMessages(readxl::read_excel(arquivo, sheet = aba, n_max = 30L, col_names = FALSE, col_types = "text"))
  if (!nrow(previa)) return(NA_integer_)
  pontos <- apply(previa, 1L, function(linha) {
    sum(grepl("codigo.*municip|cod_ibge|municipio|^uf$|estado|^[a-z]{2,4}[0-9]{4}[a-z]?$", nome_col(linha)))
  })
  linha <- which.max(pontos)
  if (!length(linha) || pontos[[linha]] < 2L) NA_integer_ else linha
}
ler_sinisa <- function(arquivo, modulo, ano) {
  for (aba in readxl::excel_sheets(arquivo)) {
    linha <- localizar_cabecalho(arquivo, aba)
    if (is.na(linha)) next
    dados <- suppressMessages(readxl::read_excel(arquivo, sheet = aba, skip = linha - 1L, guess_max = 10000L))
    nomes <- nome_col(names(dados))
    col_codigo <- which(nomes %in% c("cod_ibge", "codigo_do_ibge", "codigo_municipio", "codigo_do_municipio", "codigo_ibge"))[1L]
    if (is.na(col_codigo)) next
    codigo <- padronizar_codigo7(dados[[col_codigo]])
    mapa <- MAPA_SINISA[[modulo]]
    blocos <- lapply(names(mapa), function(cod) {
      colunas <- match(tolower(mapa[[cod]]), nomes)
      if (all(is.na(colunas))) return(NULL)
      valor <- somar_parcelas(lapply(colunas[!is.na(colunas)], function(j) para_numero(dados[[j]])))
      data.table(codigo_municipio = codigo, ano = ano, codigo_variavel = cod, valor = valor)[!is.na(codigo_municipio)]
    })
    saida <- rbindlist(blocos)
    if (!nrow(saida)) stop("Nenhum codigo SINISA esperado na aba ", aba, " de ", basename(arquivo))
    log_msg(basename(arquivo), ": aba '", aba, "', cabecalho na linha ", linha, ", ",
            length(unique(saida$codigo_municipio)), " municipios.")
    return(saida)
  }
  stop("Cabecalho com codigo IBGE nao encontrado em ", basename(arquivo))
}
arquivos_sinisa <- list.files(dir_brutos(FONTE, "sinisa"), recursive = TRUE, full.names = TRUE,
                              pattern = "Gestao.?Tecnica.?(Agua|Esgoto).*Base.?Municipal.*[.]xlsx$", ignore.case = TRUE)
longo_sinisa <- if (length(arquivos_sinisa)) {
  rbindlist(lapply(arquivos_sinisa, function(a) {
    modulo <- if (grepl("esgoto", basename(a), ignore.case = TRUE)) "esgoto" else "agua"
    ano <- as.integer(sub(".*_([0-9]{4})(_[^_]*)?[.]xlsx$", "\\1", basename(a)))
    if (is.na(ano)) stop("Ano nao identificado no nome do arquivo: ", basename(a))
    ler_sinisa(a, modulo, ano)
  }))
} else vazio()
if (nrow(longo_sinisa)) longo_sinisa[, origem := "SINISA"]

# ---- 3. Uniao das origens, duplicidades e abertura em colunas ---------------
longo <- rbind(longo_snis, longo_sinisa, fill = TRUE)
if (!nrow(longo)) stop("Nenhum dado SNIS/SINISA encontrado. Execute o script 01 e veja o README.")
longo <- longo[!is.na(codigo_municipio) & !is.na(ano) & ano >= ANO_INICIAL]
# Mesmo municipio-ano-variavel nas duas origens: prevalece o SINISA (divulgacao
# oficial consolidada). Dentro da mesma origem, registros repetidos sao
# prestadores distintos e sao somados (NA so quando todos forem NA).
longo[, prioridade := fifelse(origem == "SINISA", 1L, 2L)]
longo[, prioridade_minima := min(prioridade), by = .(codigo_municipio, ano, codigo_variavel)]
longo <- longo[prioridade == prioridade_minima]
repetidas <- longo[, .N, by = .(codigo_municipio, ano, codigo_variavel)][N > 1L]
if (nrow(repetidas)) log_msg("Somando ", nrow(repetidas), " chave(s) municipio-ano-variavel com mais de um registro.")
longo <- longo[, .(valor = soma_na(valor)), by = .(codigo_municipio, ano, codigo_variavel)]
base <- dcast(longo, codigo_municipio + ano ~ codigo_variavel, value.var = "valor")
for (cod in CODIGOS) if (!cod %in% names(base)) base[, (cod) := NA_real_]
setnames(base, CODIGOS, unname(NOMES[CODIGOS]))

# ---- 4. Indicadores derivados ------------------------------------------------
percentual <- function(numerador, denominador) {
  fifelse(!is.na(numerador) & !is.na(denominador) & denominador > 0, 100 * numerador / denominador, NA_real_)
}
# Volume de agua tratado = tratada em ETAs + por simples desinfeccao (NA so se ambos NA).
base[, volume_agua_tratado_mil_m3 := somar_parcelas(list(volume_agua_tratada_etas_mil_m3, volume_agua_tratada_desinfeccao_mil_m3))]
base[, indice_atendimento_agua_pct := percentual(populacao_total_atendida_agua, populacao_total_residente_agua)]
base[, indice_atendimento_esgoto_pct := percentual(populacao_total_atendida_esgoto, populacao_total_residente_esgoto)]
base[, indice_tratamento_esgoto_pct := percentual(volume_esgoto_tratado_mil_m3, volume_esgoto_coletado_mil_m3)]
indicadores <- setdiff(names(base), c("codigo_municipio", "ano"))
base <- base[rowSums(!is.na(base[, ..indicadores])) > 0L]

# ---- 5. Nome/UF oficiais e gravacao -----------------------------------------
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

descricoes <- c(
  populacao_urbana_residente_agua = c("G06A - Populacao urbana residente dos municipios atendidos com abastecimento de agua (SINISA: DFE0002)", "habitantes"),
  populacao_total_residente_agua = c("G12A - Populacao total residente dos municipios atendidos com abastecimento de agua (SINISA: DFE0001)", "habitantes"),
  populacao_total_atendida_agua = c("AG001 - Populacao total atendida com abastecimento de agua (SINISA: GTA0001 + GTA0002)", "habitantes"),
  economias_ativas_agua = c("AG003 - Quantidade de economias ativas de agua (SINISA: GTA0008 + GTA0015)", "economias"),
  volume_agua_produzido_mil_m3 = c("AG006 - Volume de agua produzido (SINISA: GTA1001)", "1.000 m3/ano"),
  volume_agua_tratada_etas_mil_m3 = c("AG007 - Volume de agua tratada em ETAs (SINISA: GTA1002)", "1.000 m3/ano"),
  volume_agua_tratada_desinfeccao_mil_m3 = c("AG015 - Volume de agua tratada por simples desinfeccao (SINISA: GTA1003)", "1.000 m3/ano"),
  volume_agua_tratado_mil_m3 = c("Volume de agua tratado = AG007 + AG015", "1.000 m3/ano"),
  populacao_urbana_residente_esgoto = c("G06B - Populacao urbana residente dos municipios atendidos com esgotamento sanitario (SINISA: DFE0002)", "habitantes"),
  populacao_total_residente_esgoto = c("G12B - Populacao total residente dos municipios atendidos com esgotamento sanitario (SINISA: DFE0001)", "habitantes"),
  populacao_total_atendida_esgoto = c("ES001 - Populacao total atendida com esgotamento sanitario (SINISA: GTE0001 + GTE0002)", "habitantes"),
  volume_esgoto_coletado_mil_m3 = c("ES005 - Volume de esgotos coletado (SINISA: GTE1002)", "1.000 m3/ano"),
  volume_esgoto_tratado_mil_m3 = c("ES006 - Volume de esgotos tratado (SINISA: GTE1014)", "1.000 m3/ano"),
  economias_ativas_esgoto = c("ES008 - Quantidade de economias ativas de esgotos (SINISA: GTE0006 + GTE0016)", "economias"),
  numero_paralisacoes_agua = c("QD002 - Quantidade de paralisacoes no sistema de distribuicao de agua (SINISA: GTA3001)", "paralisacoes/ano"),
  duracao_paralisacoes_horas = c("QD003 - Duracao das paralisacoes (sem equivalente no SINISA; NA em 2023+)", "horas/ano"),
  economias_atingidas_paralisacoes = c("QD004 - Quantidade de economias ativas atingidas por paralisacoes (SINISA: GTA3002)", "economias/ano"),
  amostras_cloro_residual_fora_padrao = c("QD007 - Quantidade de amostras para cloro residual com resultados fora do padrao (sem equivalente no SINISA)", "amostras/ano"),
  amostras_turbidez_fora_padrao = c("QD009 - Quantidade de amostras para turbidez com resultados fora do padrao (sem equivalente no SINISA)", "amostras/ano"),
  economias_atingidas_interrupcoes_sistematicas = c("QD015 - Quantidade de economias ativas atingidas por interrupcoes sistematicas (SINISA: GTA3005)", "economias/ano"),
  amostras_coliformes_totais_fora_padrao = c("QD027 - Quantidade de amostras para coliformes totais com resultados fora do padrao (sem equivalente no SINISA)", "amostras/ano"),
  indice_atendimento_agua_pct = c("Indice de atendimento total de agua = 100 * AG001 / G12A (pode superar 100 por inconsistencia da fonte)", "%"),
  indice_atendimento_esgoto_pct = c("Indice de atendimento total de esgoto = 100 * ES001 / G12B", "%"),
  indice_tratamento_esgoto_pct = c("Indice de tratamento de esgoto = 100 * ES006 / ES005", "%")
)
salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = names(descricoes),
  descricao = paste0(vapply(descricoes, `[`, character(1L), 1L),
                     ". Serie: SNIS 2000-2022 (exportacao da Serie Historica) e SINISA 2023+ (Base Municipal); quebra metodologica em 2023."),
  unidade = vapply(descricoes, `[`, character(1L), 2L),
  periodicidade = "anual",
  tabela = "SNIS Serie Historica - Consolidado por Municipio / SINISA Informacoes de Gestao Tecnica - Base Municipal",
  fonte_url = "https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/resultados-sinisa",
  stringsAsFactors = FALSE
))
