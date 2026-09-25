# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_ipea_suicidios.R
# FONTE: Ipea - Atlas da Violencia / SIM-DATASUS (AVIOL12_SUICID) e populacao
#        estimada IBGE (ESTIMA_PO), ambas via API do Ipeadata
# OBJETIVO: Ler os brutos, manter o nivel municipal, calcular a taxa de
#           suicidios por 100 mil habitantes e gravar a base municipal do painel.
# ENTRADAS: dados/brutos/ipea_suicidios/ipeadata_AVIOL12_SUICID.csv
#           dados/brutos/ipea_suicidios/ipeadata_ESTIMA_PO.csv
# SAIDAS: dados/tratados/ipea_suicidios/ipea_suicidios_municipal.csv
#         dados/tratados/ipea_suicidios/ipea_suicidios_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/ipea_suicidios/02_tratamento_ipea_suicidios.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "ipea_suicidios"

dicionario <- carregar_dicionario_municipios()

ler_serie_municipal <- function(serie) {
  arquivo <- file.path(dir_brutos(FONTE), paste0("ipeadata_", serie, ".csv"))
  if (!file.exists(arquivo)) stop("Bruto nao encontrado: ", arquivo, ". Execute o script 01 antes.")
  bruto <- as.data.frame(ler_csv(arquivo, colunas_texto = "TERCODIGO"))
  # Somente o nivel municipal entra (a API tambem devolve Brasil, regioes, UFs,
  # meso e microrregioes, areas minimas comparaveis).
  bruto <- bruto[remover_acentos(as.character(bruto$NIVNOME)) %in% c("Municipios", "Municipio"), , drop = FALSE]
  x <- data.frame(
    codigo_municipio = padronizar_codigo7(bruto$TERCODIGO),
    ano = as.integer(substr(as.character(bruto$VALDATA), 1L, 4L)),
    valor = suppressWarnings(as.numeric(bruto$VALVALOR)),
    stringsAsFactors = FALSE
  )
  # Recorte por UF somente para testes (PAINEL_UFS); o padrao e todo o Brasil.
  x <- x[!is.na(x$codigo_municipio) & uf_por_codigo(x$codigo_municipio) %in% UFS_ATIVAS$uf, , drop = FALSE]
  if (anyDuplicated(x[c("codigo_municipio", "ano")])) stop("Chave municipio-ano duplicada na serie ", serie, ".")
  log_msg(serie, ": ", nrow(x), " linhas municipais, ", length(unique(x$codigo_municipio)),
          " municipios, ", min(x$ano), "-", max(x$ano))
  x
}

# 1. Suicidios: contagem de obitos por residencia. Zero observado e informacao
#    valida e e preservado; a ausencia de linha permanece ausente.
suicidios <- ler_serie_municipal("AVIOL12_SUICID")
if (any(suicidios$valor < 0, na.rm = TRUE)) stop("Valores negativos na serie AVIOL12_SUICID.")
ANO_INICIAL <- ano_inicial_efetivo(min(suicidios$ano))
base <- suicidios[suicidios$ano >= ANO_INICIAL & !is.na(suicidios$valor), , drop = FALSE]
names(base)[names(base) == "valor"] <- "suicidios"

# 2. Denominador: populacao residente estimada em 1o de julho (ESTIMA_PO).
#    Populacao ausente ou nao positiva deixa a taxa vazia (nunca zero).
populacao <- ler_serie_municipal("ESTIMA_PO")
populacao$valor[!is.na(populacao$valor) & populacao$valor <= 0] <- NA_real_
chave <- function(df) paste(df$codigo_municipio, df$ano)
denominador <- populacao$valor[match(chave(base), chave(populacao))]
base$taxa_suicidios_100mil <- round(base$suicidios / denominador * 1e5, 2)
log_msg("Taxa calculada para ", sum(!is.na(base$taxa_suicidios_100mil)), " de ", nrow(base),
        " municipio-ano (sem populacao ESTIMA_PO nos demais, ex.: anos anteriores a 1992).")

# 3. Nome/UF oficiais (codigos fora do dicionario oficial sao descartados) e gravacao
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("suicidios", "taxa_suicidios_100mil"),
  descricao = c(
    "Numero de obitos por suicidio (lesoes autoprovocadas voluntariamente, CID-10 X60-X84; CID-9 E950-E959 ate 1995) por municipio de residencia, SIM/DATASUS via Atlas da Violencia (serie AVIOL12_SUICID do Ipeadata)",
    "Suicidios por 100 mil habitantes: suicidios / populacao residente estimada em 1o de julho (serie ESTIMA_PO do Ipeadata) x 100.000; vazio quando nao ha populacao para o municipio-ano"
  ),
  unidade = c("obitos", "obitos por 100 mil habitantes"),
  periodicidade = "anual",
  tabela = c("AVIOL12_SUICID", "AVIOL12_SUICID / ESTIMA_PO"),
  fonte_url = "https://www.ipeadata.gov.br/",
  stringsAsFactors = FALSE
))
