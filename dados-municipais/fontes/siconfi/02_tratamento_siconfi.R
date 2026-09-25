# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_siconfi.R
# FONTE: Secretaria do Tesouro Nacional (STN) - API de Dados Abertos do SICONFI
# OBJETIVO: Ler os JSONs por ente-exercicio (DCA anexos I-C, I-D e I-E; RREO
#           Anexo 06), selecionar as contas das quatro bases fiscais (receitas,
#           despesas por funcao, despesa com pessoal, resultados nominal e
#           primario) e gravar a base municipio-ano no esquema do painel.
# ENTRADAS: dados/brutos/siconfi/dca/<ano>/<cod_ibge>.json.gz
#           dados/brutos/siconfi/rreo/<ano>/<cod_ibge>.json.gz
#           dados/brutos/siconfi/finbra/*.csv (opcional; download manual)
# SAIDAS: dados/tratados/siconfi/siconfi_municipal.csv
#         dados/tratados/siconfi/siconfi_dicionario_variaveis.csv
#         dados/tratados/siconfi/intermediario/<endpoint>_<ano>.csv (cache das
#         linhas selecionadas; apague a pasta para reprocessar tudo)
# COMO EXECUTAR: Rscript fontes/siconfi/02_tratamento_siconfi.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "siconfi"

dicionario <- carregar_dicionario_municipios()
dir_bruto <- dir_brutos(FONTE)
dir_cache <- dir_tratados(FONTE, "intermediario")
URL_DOCS <- "https://apidatalake.tesouro.gov.br/docs/siconfi/"

# ---- 1. Contas selecionadas e formulas -----------------------------------------
# Receitas (Anexo I-C): "Receitas Brutas Realizadas" (2013: "Receitas
# Realizadas") menos as colunas "Deducoes ..." (FUNDEB etc.), ou seja, receitas
# liquidas. As naturezas sao identificadas pelo codigo sem zeros a direita,
# prefixado pelo numero de digitos: o plano ate 2017 usa 12 digitos
# (1.7.2.1.00.00.00) e o plano 2018+ usa 10 (1.7.1.0.00.0.0); a mesma natureza
# muda de significado entre os planos (ex.: 1.7.2.1 = Uniao ate 2017 e
# Participacao na Receita dos Estados em 2022+), por isso a chave inclui o formato.
chave_natureza <- function(cod_conta) {
  digitos <- gsub("[^0-9]", "", sub("^[A-Za-z]+", "", as.character(cod_conta)))
  ifelse(nzchar(digitos), paste0(nchar(digitos), ":", sub("0+$", "", digitos)), NA_character_)
}
MAPA_RECEITAS <- c(
  "12:1" = "receita_corrente",         "10:1" = "receita_corrente",
  "12:11" = "receita_tributaria",      "10:11" = "receita_tributaria",
  "12:17" = "transferencias_correntes", "10:17" = "transferencias_correntes",
  "12:1721" = "transferencias_federais", "10:171" = "transferencias_federais",
  "12:1722" = "transferencias_estaduais", "10:172" = "transferencias_estaduais",
  "12:2" = "receita_capital",          "10:2" = "receita_capital",
  # FPM: ate 2017 uma linha; 2018-2021 cota mensal + 1% julho + 1% dezembro; 2022+ total 1.7.1.1.51
  "12:17210102" = "fpm", "10:1718012" = "fpm", "10:1718013" = "fpm", "10:1718014" = "fpm", "10:171151" = "fpm",
  "12:17220101" = "icms_cota_parte", "10:1728011" = "icms_cota_parte", "10:17215" = "icms_cota_parte"
)
# Despesas por funcao (Anexo I-E, coluna Despesas Pagas): apenas as linhas de
# primeiro nivel ("10 - Saude"); somar subfuncoes ("10.301 - ...") duplicaria.
MAPA_FUNCOES <- c("10" = "despesa_saude", "12" = "despesa_educacao", "13" = "despesa_cultura",
                  "15" = "despesa_urbanismo", "16" = "despesa_habitacao", "17" = "despesa_saneamento")

INDICADORES <- data.frame(
  variavel = c("receita_total", "receita_corrente", "receita_tributaria", "transferencias_correntes",
               "transferencias_federais", "transferencias_estaduais", "fpm", "icms_cota_parte",
               "receita_capital", "despesa_total", "despesa_pessoal", "despesa_saude", "despesa_educacao",
               "despesa_cultura", "despesa_urbanismo", "despesa_habitacao", "despesa_saneamento",
               "despesa_infraestrutura", "resultado_nominal", "resultado_primario"),
  chave_anexo = c(rep("IC", 9L), rep("ID", 2L), rep("IE", 7L), rep("RREO06", 2L)),
  descricao = c(
    "Total das receitas orcamentarias realizadas, liquidas de deducoes (linha TotalReceitas)",
    "Receitas correntes realizadas, liquidas de deducoes (natureza 1.0.0.0)",
    "Impostos, taxas e contribuicoes de melhoria, liquidos de deducoes (natureza 1.1.0.0; 'Receita Tributaria' ate 2017)",
    "Transferencias correntes recebidas, liquidas de deducoes (natureza 1.7.0.0)",
    "Transferencias correntes da Uniao (1.7.2.1 ate 2017; 1.7.1.0 a partir de 2018)",
    "Transferencias correntes dos Estados (1.7.2.2 ate 2017; 1.7.2.0 a partir de 2018)",
    "Cota-parte do FPM (1.7.2.1.01.02 ate 2017; 1.7.1.8.01.2 + .3 + .4 em 2018-2021; 1.7.1.1.51 a partir de 2022)",
    "Cota-parte do ICMS (1.7.2.2.01.01 ate 2017; 1.7.2.8.01.1 em 2018-2021; 1.7.2.1.50 a partir de 2022)",
    "Receitas de capital realizadas, liquidas de deducoes (natureza 2.0.0.0)",
    "Total geral da despesa paga (linha TotalDespesas)",
    "Despesas pagas com pessoal e encargos sociais (natureza 3.1)",
    "Despesas pagas na funcao 10 - Saude", "Despesas pagas na funcao 12 - Educacao",
    "Despesas pagas na funcao 13 - Cultura", "Despesas pagas na funcao 15 - Urbanismo",
    "Despesas pagas na funcao 16 - Habitacao", "Despesas pagas na funcao 17 - Saneamento",
    "Soma das despesas pagas nas funcoes 15 - Urbanismo, 16 - Habitacao e 17 - Saneamento",
    "Resultado nominal acima da linha (sem RPPS quando discriminado), posicao de encerramento do exercicio",
    "Resultado primario acima da linha (sem RPPS quando discriminado), posicao de encerramento do exercicio"
  ),
  tabela = c(rep("DCA Anexo I-C", 9L), rep("DCA Anexo I-D", 2L), rep("DCA Anexo I-E", 7L), rep("RREO Anexo 06", 2L)),
  stringsAsFactors = FALSE
)
VAZIO <- data.frame(codigo_municipio = character(), ano = integer(), chave_anexo = character(),
                    variavel = character(), valor = numeric(), prioridade = integer(), stringsAsFactors = FALSE)

selecionar_itens <- function(itens, codigo, ano) {
  # Reduz a resposta de um ente-exercicio as linhas usadas pelos indicadores e
  # registra os anexos presentes (pseudo-variavel "_anexo_presente").
  if (!is.data.frame(itens) || !nrow(itens) ||
      !all(c("anexo", "coluna", "cod_conta", "conta", "valor") %in% names(itens))) return(NULL)
  anexo <- as.character(itens$anexo)
  chave <- rep(NA_character_, nrow(itens))
  chave[grepl("Anexo I-C$", anexo)] <- "IC"
  chave[grepl("Anexo I-D$", anexo)] <- "ID"
  chave[grepl("Anexo I-E$", anexo)] <- "IE"
  chave[grepl("RREO-Anexo 06$", anexo)] <- "RREO06"
  coluna <- normalizar_nome(itens$coluna)
  cod <- as.character(itens$cod_conta)
  conta <- trimws(as.character(itens$conta))
  natureza <- chave_natureza(cod)
  valor <- suppressWarnings(as.numeric(itens$valor))
  parcela <- valor
  variavel <- rep(NA_character_, nrow(itens))
  prioridade <- rep(1L, nrow(itens))
  # I-C: receitas realizadas (+) e deducoes (-)
  ic <- chave %in% "IC" & (grepl("^receitas .*realizadas$", coluna) | grepl("^dedu", coluna))
  variavel[ic] <- ifelse(cod[ic] == "TotalReceitas", "receita_total", unname(MAPA_RECEITAS[natureza[ic]]))
  deducao <- ic & grepl("^dedu", coluna)
  parcela[deducao] <- -valor[deducao]
  # I-D: despesas pagas (exclui as intraorcamentarias "DI")
  id <- chave %in% "ID" & coluna == "despesas pagas" & !grepl("^DI", cod)
  variavel[id & cod == "TotalDespesas"] <- "despesa_total"
  variavel[id & sub("^[0-9]+:", "", natureza) %in% "31"] <- "despesa_pessoal"
  # I-E: funcoes de primeiro nivel
  ie <- chave %in% "IE" & coluna == "despesas pagas" & grepl("^[0-9]{2} +-", conta)
  variavel[ie] <- unname(MAPA_FUNCOES[substr(conta[ie], 1L, 2L)])
  # RREO Anexo 06: resultados acima da linha, coluna VALOR (2018: VALOR INCORRIDO);
  # prefere a versao "sem RPPS" (2020+) e usa a versao unica nos anos anteriores.
  rr <- chave %in% "RREO06" & coluna %in% c("valor", "valor incorrido") & !grepl("ComRPPS", cod) &
    (grepl("AcimaDaLinha", cod) | cod == "RREO6ResultadoPrimarioEstadosMunicipios")
  variavel[rr & grepl("^ResultadoNominal", cod)] <- "resultado_nominal"
  variavel[rr & grepl("^(RREO6)?ResultadoPrimario", cod)] <- "resultado_primario"
  prioridade[rr & !grepl("SemRPPS", cod)] <- 2L
  manter <- !is.na(variavel) & !is.na(chave)
  presentes <- unique(chave[!is.na(chave)])
  rbind(
    data.frame(codigo_municipio = codigo, ano = as.integer(ano), chave_anexo = chave[manter],
               variavel = variavel[manter], valor = parcela[manter], prioridade = prioridade[manter],
               stringsAsFactors = FALSE),
    data.frame(codigo_municipio = codigo, ano = as.integer(ano), chave_anexo = presentes,
               variavel = "_anexo_presente", valor = NA_real_, prioridade = 1L, stringsAsFactors = FALSE)
  )
}

# ---- 2. Leitura dos brutos da API (com cache por endpoint-exercicio) ------------
ler_json_gz <- function(arquivo) {
  con <- gzfile(arquivo, open = "rt")
  on.exit(close(con))
  texto <- paste(readLines(con, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  jsonlite::fromJSON(texto, simplifyVector = TRUE, simplifyDataFrame = TRUE, simplifyMatrix = FALSE)$items
}

ler_selecao_ano <- function(endpoint, ano) {
  arquivos <- list.files(file.path(dir_bruto, endpoint, ano), pattern = "^[0-9]{7}[.]json[.]gz$", full.names = TRUE)
  if (!length(arquivos)) return(NULL)
  cache <- file.path(dir_cache, paste0(endpoint, "_", ano, ".csv"))
  if (file.exists(cache) && file.mtime(cache) > max(file.mtime(arquivos))) return(as.data.frame(ler_csv(cache)))
  log_msg("Lendo ", length(arquivos), " arquivo(s) de ", endpoint, " ", ano, ".")
  partes <- lapply(arquivos, function(a) selecionar_itens(ler_json_gz(a), substr(basename(a), 1L, 7L), ano))
  selecao <- rbind(VAZIO, do.call(rbind, partes))
  escrever_csv(selecao, cache)
  selecao
}

listar_anos <- function(endpoint) {
  anos <- suppressWarnings(as.integer(list.dirs(file.path(dir_bruto, endpoint), full.names = FALSE, recursive = FALSE)))
  sort(anos[!is.na(anos)])
}
selecoes <- c(lapply(listar_anos("dca"), function(a) ler_selecao_ano("dca", a)),
              lapply(listar_anos("rreo"), function(a) ler_selecao_ano("rreo", a)))
sel_api <- rbind(VAZIO, do.call(rbind, selecoes))

# ---- 3. FINBRA (opcional): CSVs anuais por anexo, baixados manualmente ---------
# Leiaute esperado da consulta FINBRA (Dados Contabeis > CSV): linhas iniciais de
# metadados ("Ano:2019;Anexo:DCA-Anexo I-C;..."), cabecalho
# "Instituicao;Cod.IBGE;UF;Populacao;Coluna;Conta;Valor", separador ";",
# decimal "," e codificacao Latin-1. NAO testado com arquivo real: confira a
# primeira carga. Usado apenas para ente-exercicios sem arquivo da API.
ler_finbra <- function(arquivo) {
  linhas <- iconv(readLines(arquivo, warn = FALSE, encoding = "latin1"), from = "latin1", to = "UTF-8")
  cabecalho <- grep("cod[.]? ?ibge", linhas, ignore.case = TRUE)[1L]
  if (is.na(cabecalho)) stop("FINBRA sem cabecalho reconhecivel (Cod.IBGE): ", basename(arquivo))
  meta <- paste(linhas[seq_len(cabecalho - 1L)], collapse = ";")
  ano <- suppressWarnings(as.integer(sub(".*Ano:\\s*([0-9]{4}).*", "\\1", meta)))
  anexo <- regmatches(meta, regexpr("I-(C|D|E)", meta))
  if (is.na(ano) || !length(anexo)) stop("FINBRA sem 'Ano:' ou 'Anexo I-C/I-D/I-E' nos metadados: ", basename(arquivo))
  x <- utils::read.table(text = linhas[cabecalho:length(linhas)], sep = ";", header = TRUE, quote = "\"",
                         dec = ",", stringsAsFactors = FALSE, check.names = FALSE, comment.char = "", fill = TRUE)
  nomes <- normalizar_nome(names(x))
  pegar <- function(padrao) {
    j <- which(grepl(padrao, nomes))[1L]
    if (is.na(j)) stop("FINBRA sem a coluna '", padrao, "': ", basename(arquivo))
    x[[j]]
  }
  conta <- trimws(as.character(pegar("^conta")))
  codigo_conta <- sub("\\s.*$", "", conta)          # "1.1.0.0.00.0.0 - Impostos..." -> "1.1.0.0.00.0.0"
  total <- grepl("^total", normalizar_nome(conta))
  cod_conta <- switch(anexo,
    "I-C" = ifelse(total, "TotalReceitas", paste0("RO", codigo_conta)),
    "I-D" = ifelse(total, "TotalDespesas", paste0("DO", codigo_conta)),
    "I-E" = rep("TotalDespesas", length(conta)))
  data.frame(exercicio = ano, cod_ibge = padronizar_codigo7(pegar("ibge")), anexo = paste0("DCA-Anexo ", anexo),
             coluna = as.character(pegar("^coluna")), cod_conta = cod_conta, conta = conta,
             valor = para_numero(pegar("^valor")), stringsAsFactors = FALSE)
}

sel_finbra <- VAZIO
for (arquivo in list.files(file.path(dir_bruto, "finbra"), pattern = "[.]csv$", full.names = TRUE, ignore.case = TRUE)) {
  itens <- ler_finbra(arquivo)
  log_msg("FINBRA ", basename(arquivo), ": ", nrow(itens), " linhas (", itens$anexo[1L], ", ", itens$exercicio[1L], ").")
  partes <- lapply(split(itens, itens$cod_ibge), function(x) selecionar_itens(x, x$cod_ibge[1L], x$exercicio[1L]))
  sel_finbra <- rbind(sel_finbra, do.call(rbind, partes))
}
com_api <- unique(paste(sel_api$codigo_municipio, sel_api$ano)[sel_api$chave_anexo != "RREO06"])
sel_finbra <- sel_finbra[!paste(sel_finbra$codigo_municipio, sel_finbra$ano) %in% com_api, , drop = FALSE]
sel <- rbind(sel_api, sel_finbra)
if (!nrow(sel)) stop("Nenhum bruto encontrado. Execute o script 01 (ou coloque CSVs FINBRA em dados/brutos/siconfi/finbra).")

# ---- 4. Agregacao, zeros estruturais e base larga municipio-ano ----------------
valores <- sel[sel$variavel != "_anexo_presente", , drop = FALSE]
valores <- valores[order(valores$prioridade), , drop = FALSE]
# resultados: uma unica linha por indicador (menor prioridade vence); demais: soma das parcelas
resultados <- valores[valores$chave_anexo == "RREO06", , drop = FALSE]
resultados <- resultados[!duplicated(resultados[c("codigo_municipio", "ano", "variavel")]),
                         c("codigo_municipio", "ano", "variavel", "valor"), drop = FALSE]
dca <- valores[valores$chave_anexo != "RREO06", , drop = FALSE]
somar <- function(v) if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE)
agregado <- if (nrow(dca)) {
  aggregate(valor ~ codigo_municipio + ano + variavel, data = dca, FUN = somar, na.action = na.pass)
} else dca[c("codigo_municipio", "ano", "variavel", "valor")]
agregado <- rbind(agregado, resultados)
agregado$presente <- TRUE

# Grade: todos os indicadores cujo anexo foi entregue pelo ente no exercicio.
# Linha de conta ausente em anexo DCA entregue = zero estrutural; anexo ausente
# (nao declarante) = NA; no RREO, linha ausente fica NA. Nunca se imputa.
presenca <- unique(sel[sel$variavel == "_anexo_presente", c("codigo_municipio", "ano", "chave_anexo")])
grade <- merge(presenca, INDICADORES[INDICADORES$variavel != "despesa_infraestrutura", c("variavel", "chave_anexo")],
               by = "chave_anexo")
longo <- merge(grade, agregado, by = c("codigo_municipio", "ano", "variavel"), all.x = TRUE)
longo$valor[is.na(longo$presente) & longo$chave_anexo != "RREO06"] <- 0

base <- unique(longo[c("codigo_municipio", "ano")])
chave_base <- paste(base$codigo_municipio, base$ano)
for (v in setdiff(INDICADORES$variavel, "despesa_infraestrutura")) {
  parte <- longo[longo$variavel == v, , drop = FALSE]
  base[[v]] <- parte$valor[match(chave_base, paste(parte$codigo_municipio, parte$ano))]
}
infra <- base[c("despesa_urbanismo", "despesa_habitacao", "despesa_saneamento")]
base$despesa_infraestrutura <- ifelse(rowSums(!is.na(infra)) == 0L, NA_real_, rowSums(infra, na.rm = TRUE))
indicadores <- setdiff(names(base), c("codigo_municipio", "ano"))
base <- base[rowSums(!is.na(base[indicadores])) > 0L, , drop = FALSE]
log_msg("Municipio-anos com dados: ", nrow(base), " (", min(base$ano), "-", max(base$ano), ").")

# ---- 5. Nome/UF oficiais, gravacao e dicionario ---------------------------------
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)
salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = INDICADORES$variavel,
  descricao = INDICADORES$descricao,
  unidade = "R$ correntes (nominais)",
  periodicidade = "anual",
  tabela = INDICADORES$tabela,
  fonte_url = URL_DOCS,
  stringsAsFactors = FALSE
))
