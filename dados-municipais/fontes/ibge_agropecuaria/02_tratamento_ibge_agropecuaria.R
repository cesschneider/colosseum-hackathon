# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_ibge_agropecuaria.R
# FONTE: IBGE/SIDRA - PAM (tabelas 1612 e 1613) e PPM/aquicultura (tabela 3940)
# OBJETIVO: Ler os brutos, converter os simbolos do SIDRA e montar uma linha por
#           municipio-ano com valor da producao e area colhida das lavouras
#           (temporarias, permanentes e total), valor e producao em kg da
#           aquicultura, mais as versoes deflacionadas pelo IPCA dos valores.
# ENTRADAS: dados/brutos/ibge_agropecuaria/sidra_*.rds
#           dados/brutos/ibge_agropecuaria/deflator_ipca_anual.csv
# SAIDAS: dados/tratados/ibge_agropecuaria/ibge_agropecuaria_municipal.csv
#         dados/tratados/ibge_agropecuaria/ibge_agropecuaria_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/ibge_agropecuaria/02_tratamento_ibge_agropecuaria.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "ibge_agropecuaria"

dicionario <- carregar_dicionario_municipios()
dir_entrada <- dir_brutos(FONTE)
CHAVE <- c("codigo_municipio", "ano")

# 1. Leitura dos brutos. Simbolos do SIDRA no campo Valor:
#    "-"   = zero absoluto (nao resultante de arredondamento)  -> 0
#    "..." = nao se aplica (ex.: municipio ainda nao instalado) -> NA
#    ".."  = nao disponivel; "X" = omitido por sigilo          -> NA
#    Os tres ultimos ja viram NA em sidra_padronizar; o "-" e tratado aqui.
ler_sidra <- function(nome) {
  arquivo <- file.path(dir_entrada, paste0(nome, ".rds"))
  if (!file.exists(arquivo)) stop("Bruto ausente: ", arquivo, ". Execute o script 01 antes.")
  bruto <- readRDS(arquivo)
  bruto$Valor[trimws(as.character(bruto$Valor)) == "-"] <- "0"
  dados <- sidra_padronizar(bruto)
  if (any(dados$valor < 0, na.rm = TRUE)) stop(nome, ": valor negativo na fonte.")
  dados
}

# Valor da producao (variavel 215) da PAM: a unidade muda ao longo da serie
# (Mil Cruzeiros, Mil Cruzados, Mil Cruzados Novos, Mil Cruzeiros Reais ate
# 1993; Mil Reais de 1994 em diante). Somente os anos em Mil Reais sao
# comparaveis; os demais ficam NA. A area colhida (hectares) vale desde 1974.
somente_mil_reais <- function(dados) {
  fora <- dados$variavel_codigo == "215" & !dados$unidade %in% "Mil Reais"
  if (any(fora)) {
    log_msg("Valor da producao em moeda anterior ao Real (", min(dados$ano[fora]), "-",
            max(dados$ano[fora]), ") descartado: ", sum(fora), " registros -> NA.")
    dados$valor[fora] <- NA_real_
  }
  dados
}

# Uma coluna por variavel: mapa = c("215" = "nome_da_coluna", ...).
para_largo <- function(dados, mapa) {
  if (anyDuplicated(dados[c(CHAVE, "variavel_codigo")])) stop("Chave municipio-ano-variavel duplicada.")
  saida <- NULL
  for (codigo in names(mapa)) {
    parte <- dados[dados$variavel_codigo == codigo, c(CHAVE, "valor")]
    names(parte)[3L] <- mapa[[codigo]]
    saida <- if (is.null(saida)) parte else merge(saida, parte, by = CHAVE, all = TRUE)
  }
  saida
}

temporarias <- para_largo(somente_mil_reais(ler_sidra("sidra_1612_lavouras_temporarias")),
                          c("215" = "valor_producao_lavouras_temporarias",
                            "216" = "area_colhida_temporarias"))
permanentes <- para_largo(somente_mil_reais(ler_sidra("sidra_1613_lavouras_permanentes")),
                          c("215" = "valor_producao_lavouras_permanentes",
                            "216" = "area_colhida_permanentes"))
aquicultura <- para_largo(ler_sidra("sidra_3940_aquicultura_valor"),
                          c("215" = "valor_producao_aquicultura"))

# 2. Producao da aquicultura em kg: soma dos produtos medidos em quilogramas
#    por municipio-ano. NA somente quando nenhum produto tem valor.
kg <- ler_sidra("sidra_3940_aquicultura_producao_kg")
col_produto <- names(kg)[remover_acentos(names(kg)) == "Tipo de produto da aquicultura (Codigo)"][1L]
if (is.na(col_produto)) stop("Bruto da aquicultura sem a coluna de codigo do produto.")
if (any(kg$unidade %in% "Milheiros")) stop("Produto medido em milheiros na soma em quilogramas.")
if (anyDuplicated(kg[c(CHAVE, col_produto)])) stop("Chave municipio-ano-produto duplicada na aquicultura.")
log_msg("Aquicultura em kg: ", length(unique(kg[[col_produto]])), " produtos somados.")
producao_kg <- aggregate(list(producao_aquicultura_kg = kg$valor), by = kg[CHAVE],
                         FUN = function(v) if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE))

# 3. Base municipio-ano. Totais agricolas = temporarias + permanentes somente
#    quando os dois componentes existem (NA se qualquer um faltar).
base <- Reduce(function(a, b) merge(a, b, by = CHAVE, all = TRUE),
               list(temporarias, permanentes, aquicultura, producao_kg))
base$valor_producao_agricola_total <- base$valor_producao_lavouras_temporarias + base$valor_producao_lavouras_permanentes
base$area_colhida_total <- base$area_colhida_temporarias + base$area_colhida_permanentes
base <- base[c(CHAVE, "valor_producao_lavouras_temporarias", "valor_producao_lavouras_permanentes",
               "valor_producao_agricola_total", "area_colhida_temporarias", "area_colhida_permanentes",
               "area_colhida_total", "valor_producao_aquicultura", "producao_aquicultura_kg")]

indicadores <- setdiff(names(base), CHAVE)
sem_dado <- rowSums(!is.na(base[indicadores])) == 0
log_msg("Descartadas ", sum(sem_dado), " linhas municipio-ano sem nenhum dado (ex.: municipio ainda nao instalado).")
base <- base[!sem_dado, ]

# 4. Valores a precos constantes (IPCA, media anual; ver script 01). O ano de
#    1994 e descartado porque o deflator da biblioteca cobre so dezembro/1994.
arquivo_deflator <- file.path(dir_entrada, "deflator_ipca_anual.csv")
if (!file.exists(arquivo_deflator)) stop("Bruto ausente: ", arquivo_deflator, ". Execute o script 01 antes.")
deflator <- as.data.frame(ler_csv(arquivo_deflator))
deflator <- deflator[deflator$ano >= 1995L, ]
ano_base <- unique(deflator$ano_base)
if (length(ano_base) != 1L) stop("Deflator com ano-base ambiguo.")
fator <- deflator$fator[match(base$ano, deflator$ano)]
monetarias <- c("valor_producao_lavouras_temporarias", "valor_producao_lavouras_permanentes",
                "valor_producao_agricola_total", "valor_producao_aquicultura")
for (v in monetarias) base[[paste0(v, "_reais_", ano_base)]] <- base[[v]] * fator

# 5. Nome/UF oficiais e gravacao
base <- juntar_dicionario(base, dicionario)
ufs_faltantes <- setdiff(UFS_ATIVAS$uf, unique(base$uf))
if (length(ufs_faltantes)) {
  stop("Brutos sem municipios de: ", paste(ufs_faltantes, collapse = ", "),
       ". Rode o script 01 com PAINEL_REBAIXAR=TRUE.")
}
salvar_base_tratada(FONTE, base)

url_pam <- c("https://sidra.ibge.gov.br/tabela/1612", "https://sidra.ibge.gov.br/tabela/1613")
url_ppm <- "https://sidra.ibge.gov.br/tabela/3940"
dic <- data.frame(
  variavel = c("valor_producao_lavouras_temporarias", "valor_producao_lavouras_permanentes",
               "valor_producao_agricola_total", "area_colhida_temporarias", "area_colhida_permanentes",
               "area_colhida_total", "valor_producao_aquicultura", "producao_aquicultura_kg"),
  descricao = c("Valor da producao das lavouras temporarias (PAM, total dos produtos)",
                "Valor da producao das lavouras permanentes (PAM, total dos produtos)",
                "Valor da producao agricola: lavouras temporarias + permanentes (NA se um componente falta)",
                "Area colhida das lavouras temporarias (PAM, total dos produtos)",
                "Area colhida das lavouras permanentes (PAM, total dos produtos)",
                "Area colhida agricola: lavouras temporarias + permanentes (NA se um componente falta)",
                "Valor da producao da aquicultura (PPM, total dos produtos)",
                paste("Producao da aquicultura: soma de 21 produtos medidos em quilogramas (peixes, camarao,",
                      "ostras/vieiras/mexilhoes e outros produtos); exclui alevinos, larvas e sementes (milheiros)")),
  unidade = c("mil R$ correntes", "mil R$ correntes", "mil R$ correntes", "hectares", "hectares",
              "hectares", "mil R$ correntes", "kg"),
  tabela = c("SIDRA 1612", "SIDRA 1613", "SIDRA 1612 e 1613", "SIDRA 1612", "SIDRA 1613",
             "SIDRA 1612 e 1613", "SIDRA 3940", "SIDRA 3940"),
  fonte_url = c(url_pam[1L], url_pam[2L], url_pam[1L], url_pam[1L], url_pam[2L], url_pam[1L], url_ppm, url_ppm),
  stringsAsFactors = FALSE
)
dic_reais <- dic[dic$variavel %in% monetarias, ]
dic_reais$variavel <- paste0(dic_reais$variavel, "_reais_", ano_base)
dic_reais$descricao <- paste0(dic_reais$descricao, ", a precos de ", ano_base,
                              " (IPCA, media anual; disponivel de 1995 em diante)")
dic_reais$unidade <- paste0("mil R$ de ", ano_base)
dic <- rbind(dic, dic_reais)
dic$periodicidade <- "anual"
salvar_dicionario_variaveis(FONTE, dic)
