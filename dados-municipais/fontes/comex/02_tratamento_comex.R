# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_comex.R
# FONTE: SECEX/MDIC - Comex Stat, exportacoes e importacoes por municipio
# OBJETIVO: Ler os brutos anuais (municipio-mes-SH4-pais), agregar por
#           municipio-mes e municipio-ano e gravar as bases do painel:
#           exportacoes totais e agropecuarias, importacoes e saldo comercial.
# ENTRADAS: dados/brutos/comex/EXP_<ANO>_MUN.csv e IMP_<ANO>_MUN.csv
# SAIDAS: dados/tratados/comex/comex_municipal.csv          (municipio-ano)
#         dados/tratados/comex/comex_mensal_municipal.csv   (municipio-ano-mes)
#         dados/tratados/comex/comex_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/comex/02_tratamento_comex.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table"))
library(data.table)
FONTE <- "comex"

# Regra agropecuaria preservada do projeto de origem: SH4 < 1601, isto e,
# capitulos 01 a 15 do Sistema Harmonizado (animais vivos, vegetais, gorduras
# e oleos). A partir do capitulo 16 comecam os produtos da industria alimentar.
SH4_AGRO_LIMITE <- 1601L
COLUNAS <- c("CO_ANO", "CO_MES", "SH4", "CO_MUN", "VL_FOB")
INDICADORES <- c("exportacoes_fob_usd", "exportacoes_agro_fob_usd",
                 "importacoes_fob_usd", "importacoes_agro_fob_usd", "saldo_comercial_fob_usd")

dicionario <- carregar_dicionario_municipios()
arquivos <- list.files(dir_brutos(FONTE), pattern = "^(EXP|IMP)_[0-9]{4}_MUN[.]csv$", full.names = TRUE)
if (!length(arquivos)) stop("Nenhum bruto encontrado. Execute o script 01 antes.")

# 1. Leitura seletiva (5 colunas) e agregacao municipio-mes de cada arquivo.
#    CO_MUN e o codigo IBGE de 7 digitos (com digito verificador); codigos
#    textuais garantem a preservacao dos zeros a esquerda.
agregar_arquivo <- function(arquivo) {
  fluxo <- substr(basename(arquivo), 1L, 3L)
  ano_nome <- as.integer(substr(basename(arquivo), 5L, 8L))
  cabecalho <- names(fread(arquivo, sep = ";", nrows = 0L, encoding = "UTF-8"))
  ausentes <- setdiff(COLUNAS, cabecalho)
  if (length(ausentes)) stop(basename(arquivo), " sem colunas: ", paste(ausentes, collapse = ", "))
  x <- fread(arquivo, sep = ";", select = COLUNAS, colClasses = "character",
             encoding = "UTF-8", na.strings = c("", "NA"))
  setnames(x, COLUNAS, c("ano", "mes", "sh4", "codigo_municipio", "valor_fob"))
  x[, `:=`(ano = as.integer(ano), mes = as.integer(mes),
           sh4 = suppressWarnings(as.integer(sh4)), valor_fob = as.numeric(valor_fob),
           codigo_municipio = padronizar_codigo7(codigo_municipio))]
  # Checagens minimas: um arquivo truncado ou trocado nao pode entrar na serie.
  if (!nrow(x) || any(x$ano != ano_nome, na.rm = TRUE)) stop("Ano interno diverge do nome em ", basename(arquivo))
  if (any(!x$mes %in% 1:12)) stop("Mes invalido em ", basename(arquivo))
  if (anyNA(x$valor_fob) || any(x$valor_fob < 0)) stop("VL_FOB invalido em ", basename(arquivo))
  agregado <- x[!is.na(codigo_municipio), .(
    total = sum(valor_fob),
    agro = sum(valor_fob[!is.na(sh4) & sh4 < SH4_AGRO_LIMITE])
  ), by = .(codigo_municipio, ano, mes)]
  agregado[, fluxo := fluxo]
  log_msg(basename(arquivo), ": ", nrow(x), " linhas, ", uniqueN(agregado$codigo_municipio),
          " municipios, meses 1-", max(x$mes))
  agregado
}
mensal_longo <- rbindlist(lapply(arquivos, agregar_arquivo))

# Cada ano precisa dos dois fluxos; sem um deles, o saldo sairia errado.
anos_incompletos <- unique(mensal_longo[, .(ano, fluxo)])[, .N, by = ano][N < 2L, ano]
if (length(anos_incompletos)) stop("Anos sem EXP ou sem IMP: ", paste(anos_incompletos, collapse = ", "))

# 2. Municipio-mes em formato largo. A ausencia de registro de um fluxo em um
#    municipio-mes significa que nao houve operacao registrada (US$ 0): a base
#    da aduana e exaustiva, nao ha "dado faltante".
mensal <- dcast(mensal_longo, codigo_municipio + ano + mes ~ fluxo,
                value.var = c("total", "agro"), fill = 0)
setnames(mensal, c("total_EXP", "agro_EXP", "total_IMP", "agro_IMP"),
         c("exportacoes_fob_usd", "exportacoes_agro_fob_usd",
           "importacoes_fob_usd", "importacoes_agro_fob_usd"))
mensal[, saldo_comercial_fob_usd := exportacoes_fob_usd - importacoes_fob_usd]

# 3. Nome/UF oficiais (descarta codigos fora do dicionario, ex.: municipio nao
#    declarado) e base anual por soma dos meses. O ano corrente e parcial.
mensal <- as.data.table(juntar_dicionario(mensal, dicionario))
anual <- mensal[, lapply(.SD, sum), by = .(codigo_municipio, nome_municipio, uf, ano), .SDcols = INDICADORES]

salvar_base_tratada(FONTE, anual)
salvar_base_tratada(FONTE, mensal, nome = "comex_mensal_municipal", mensal = TRUE)

# 4. Dicionario de variaveis (as duas tabelas compartilham os indicadores).
descricoes <- c(
  exportacoes_fob_usd = "Valor total das exportacoes do municipio, todos os produtos e destinos",
  exportacoes_agro_fob_usd = "Valor das exportacoes agropecuarias: capitulos 01 a 15 do Sistema Harmonizado (SH4 < 1601)",
  importacoes_fob_usd = "Valor total das importacoes do municipio, todos os produtos e origens",
  importacoes_agro_fob_usd = "Valor das importacoes agropecuarias: capitulos 01 a 15 do Sistema Harmonizado (SH4 < 1601)",
  saldo_comercial_fob_usd = "Saldo comercial: exportacoes menos importacoes"
)
dicionario_variaveis <- rbind(
  data.frame(variavel = names(descricoes), descricao = unname(descricoes),
             periodicidade = "anual", tabela = "comex_municipal", stringsAsFactors = FALSE),
  data.frame(variavel = names(descricoes), descricao = paste(unname(descricoes), "(acumulado no mes)"),
             periodicidade = "mensal", tabela = "comex_mensal_municipal", stringsAsFactors = FALSE)
)
dicionario_variaveis$unidade <- "US$ FOB correntes"
dicionario_variaveis$fonte_url <- "https://comexstat.mdic.gov.br/pt/home"
salvar_dicionario_variaveis(FONTE, dicionario_variaveis)
