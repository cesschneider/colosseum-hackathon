# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_datasus_populacao.R
# FONTE: DataSUS/TabNet - Estimativas populacionais por municipio, idade e sexo
# OBJETIVO: Ler as respostas brutas do TabNet (.prn dentro de HTML latin1),
#           somar as faixas etarias em grandes grupos e calcular as razoes de
#           dependencia e o indice de envelhecimento por municipio-ano.
# ENTRADAS: dados/brutos/datasus_populacao/datasus_populacao_faixa_etaria_<ano>.html
# SAIDAS: dados/tratados/datasus_populacao/datasus_populacao_municipal.csv
#         dados/tratados/datasus_populacao/datasus_populacao_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/datasus_populacao/02_tratamento_datasus_populacao.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "datasus_populacao"

dicionario <- carregar_dicionario_municipios()
arquivos <- list.files(dir_brutos(FONTE), pattern = "^datasus_populacao_faixa_etaria_[0-9]{4}[.]html$",
                       full.names = TRUE)
if (!length(arquivos)) stop("Nenhum bruto encontrado. Execute o script 01 antes.")
anos <- as.integer(sub(".*_([0-9]{4})[.]html$", "\\1", basename(arquivos)))
manter <- anos >= ano_inicial_efetivo(2000L)
arquivos <- arquivos[manter]
anos <- anos[manter]
if (!length(arquivos)) stop("Nenhum bruto no periodo solicitado.")

# Faixas etarias publicadas pelo TabNet (Faixa Etaria 1), na ordem das colunas.
FAIXAS <- c("pop_0_4", "pop_5_9", "pop_10_14", "pop_15_19", "pop_20_29", "pop_30_39",
            "pop_40_49", "pop_50_59", "pop_60_69", "pop_70_79", "pop_80_mais")

numero_tabnet <- function(x) {
  # No .prn do TabNet "-" significa zero e "..." significa nao disponivel.
  x <- trimws(as.character(x))
  x[x == "-"] <- "0"
  x[x %in% c("", "...", "NA")] <- NA_character_
  suppressWarnings(as.numeric(gsub("[^0-9]", "", x)))
}

ler_resposta_tabnet <- function(arquivo, ano) {
  # A resposta e HTML em latin1; a tabela fica dentro de <PRE>: linhas entre
  # aspas separadas por ";" (cabecalho, um municipio "CCCCCC NOME" por linha e
  # a linha "Total", que e descartada).
  texto <- iconv(rawToChar(readBin(arquivo, "raw", file.info(arquivo)$size)), from = "latin1", to = "UTF-8")
  if (grepl("Tabela de convers|<h1>ERRO", texto, ignore.case = TRUE)) {
    stop("Pagina de erro do TabNet em ", basename(arquivo))
  }
  linhas <- strsplit(texto, "\\r?\\n")[[1L]]
  cabecalho <- grep('^"Munic', linhas, value = TRUE)[1L]
  if (is.na(cabecalho) || !grepl('"0 a 4 anos".*"80 anos e mais".*"Total"', cabecalho)) {
    stop("Cabecalho inesperado em ", basename(arquivo))
  }
  tabela <- utils::read.table(text = grep('^"[0-9]{6} ', linhas, value = TRUE), sep = ";", quote = "\"",
                              header = FALSE, colClasses = "character", comment.char = "",
                              stringsAsFactors = FALSE)
  if (ncol(tabela) != length(FAIXAS) + 2L) {
    stop("Esquema inesperado (", ncol(tabela), " colunas) em ", basename(arquivo))
  }
  names(tabela) <- c("municipio", FAIXAS, "pop_total")
  for (v in c(FAIXAS, "pop_total")) tabela[[v]] <- numero_tabnet(tabela[[v]])
  tabela$codigo6 <- substr(tabela$municipio, 1L, 6L)
  if (anyDuplicated(tabela$codigo6)) stop("Codigos municipais duplicados em ", basename(arquivo))
  tabela$ano <- as.integer(ano)
  tabela[c("codigo6", "ano", FAIXAS, "pop_total")]
}

# ---- 1. Leitura, empilhamento e codigo de 7 digitos ------------------------------
log_msg("Lendo ", length(arquivos), " respostas do TabNet (", min(anos), "-", max(anos), ")")
bruto <- do.call(rbind, Map(ler_resposta_tabnet, arquivos, anos))
bruto <- bruto[substr(bruto$codigo6, 1L, 2L) %in% sprintf("%02d", UFS_ATIVAS$cod_uf), ]
bruto$codigo_municipio <- codigo6_para_7(bruto$codigo6, dicionario)
sem_codigo <- unique(bruto$codigo6[is.na(bruto$codigo_municipio)])
if (length(sem_codigo)) {
  log_msg("Aviso: ", length(sem_codigo), " codigo(s) do TabNet fora do dicionario oficial (descartados). Ex.: ",
          paste(head(sem_codigo, 5L), collapse = ", "))
}
bruto <- bruto[!is.na(bruto$codigo_municipio), ]

# ---- 2. Grandes grupos etarios e indicadores -------------------------------------
# Metodologia: jovens = 0-14 anos; potencialmente ativos = 15-59 anos;
# idosos = 60 anos ou mais (as faixas do TabNet nao permitem o corte em 65).
base <- data.frame(
  codigo_municipio = bruto$codigo_municipio,
  ano = bruto$ano,
  populacao_total = bruto$pop_total,
  populacao_0_14 = bruto$pop_0_4 + bruto$pop_5_9 + bruto$pop_10_14,
  populacao_15_59 = bruto$pop_15_19 + bruto$pop_20_29 + bruto$pop_30_39 + bruto$pop_40_49 + bruto$pop_50_59,
  populacao_60_mais = bruto$pop_60_69 + bruto$pop_70_79 + bruto$pop_80_mais,
  stringsAsFactors = FALSE
)
# Controle: a soma das faixas deve reproduzir o total publicado (detecta
# respostas truncadas ou colunas trocadas).
soma <- base$populacao_0_14 + base$populacao_15_59 + base$populacao_60_mais
divergentes <- which(!is.na(soma) & !is.na(base$populacao_total) & soma != base$populacao_total)
if (length(divergentes)) {
  stop("Soma das faixas diferente do total em ", length(divergentes), " municipio-ano. Ex.: ",
       paste(head(paste(base$codigo_municipio[divergentes], base$ano[divergentes]), 5L), collapse = "; "))
}
razao <- function(numerador, denominador) {
  ifelse(!is.na(denominador) & denominador > 0, numerador / denominador, NA_real_)
}
base$razao_dependencia_jovem <- razao(base$populacao_0_14, base$populacao_15_59)
base$razao_dependencia_idosa <- razao(base$populacao_60_mais, base$populacao_15_59)
base$razao_dependencia_total <- razao(base$populacao_0_14 + base$populacao_60_mais, base$populacao_15_59)
base$indice_envelhecimento <- 100 * razao(base$populacao_60_mais, base$populacao_0_14)

# ---- 3. Nome/UF oficiais e gravacao ---------------------------------------------
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("populacao_total", "populacao_0_14", "populacao_15_59", "populacao_60_mais",
               "razao_dependencia_jovem", "razao_dependencia_idosa", "razao_dependencia_total",
               "indice_envelhecimento"),
  descricao = c(
    "Populacao residente estimada, todas as idades (total publicado pelo TabNet)",
    "Populacao residente de 0 a 14 anos (faixas 0-4, 5-9 e 10-14)",
    "Populacao residente de 15 a 59 anos (faixas 15-19 a 50-59)",
    "Populacao residente de 60 anos ou mais (faixas 60-69, 70-79 e 80+)",
    "Razao de dependencia jovem: populacao de 0-14 anos dividida pela populacao de 15-59 anos",
    "Razao de dependencia idosa: populacao de 60 anos ou mais dividida pela populacao de 15-59 anos",
    "Razao de dependencia total: populacao de 0-14 e de 60+ anos dividida pela populacao de 15-59 anos",
    "Indice de envelhecimento: pessoas de 60 anos ou mais para cada 100 pessoas de 0-14 anos"
  ),
  unidade = c(rep("habitantes", 4L), rep("razao (proporcao; 0,20 = 20 dependentes por 100 pessoas de 15-59 anos)", 3L),
              "idosos por 100 jovens"),
  periodicidade = "anual",
  tabela = "Populacao Residente - Estimativas Populacionais por Municipio, Idade e Sexo (Faixa Etaria 1)",
  fonte_url = "http://tabnet.datasus.gov.br/cgi/deftohtm.exe?ibge/cnv/popsvs2024br.def",
  stringsAsFactors = FALSE
))
