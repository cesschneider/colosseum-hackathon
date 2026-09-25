# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_ibge_pib_municipal.R
# FONTE: IBGE - Produto Interno Bruto dos Municipios (tabela SIDRA 5938)
# OBJETIVO: Ler o bruto do SIDRA, abrir as sete variaveis em colunas (uma linha
#           por municipio-ano, valores correntes em mil reais), calcular o PIB
#           per capita com a populacao do Ipeadata e gravar a base municipal.
# ENTRADAS: dados/brutos/ibge_pib_municipal/sidra_5938_pib_municipal.rds
#           dados/brutos/ibge_pib_municipal/ipeadata_POPTOT.csv
#           dados/brutos/ibge_pib_municipal/ipeadata_ESTIMA_PO.csv
# SAIDAS: dados/tratados/ibge_pib_municipal/ibge_pib_municipal_municipal.csv
#         dados/tratados/ibge_pib_municipal/ibge_pib_municipal_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/ibge_pib_municipal/02_tratamento_ibge_pib_municipal.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "ibge_pib_municipal"

# Codigo da variavel no SIDRA -> nome da coluna na base tratada
VARIAVEIS <- c("37" = "pib", "498" = "vab_total", "513" = "vab_agropecuaria",
               "517" = "vab_industria", "6575" = "vab_servicos",
               "525" = "vab_adm_publica", "543" = "impostos_liquidos")
TOLERANCIA_IDENTIDADE <- 5   # mil reais, para os avisos de consistencia contabil
dir_entrada <- dir_brutos(FONTE)
dicionario <- carregar_dicionario_municipios()

exigir_bruto <- function(nome) {
  arquivo <- file.path(dir_entrada, nome)
  if (!file.exists(arquivo)) stop("Bruto nao encontrado (execute o script 01 antes): ", arquivo)
  arquivo
}

# 1. Leitura e padronizacao do retorno do SIDRA
bruto <- readRDS(exigir_bruto("sidra_5938_pib_municipal.rds"))
longo <- sidra_padronizar(bruto)
# Convencao do SIDRA: "-" e zero absoluto; "...", ".." e "X" sao
# indisponibilidades e ficam NA (ex.: componentes do VAB ainda nao divulgados
# para os anos mais recentes; municipios instalados depois do ano).
longo$valor[trimws(as.character(bruto[["Valor"]])) == "-"] <- 0
longo <- longo[longo$variavel_codigo %in% names(VARIAVEIS),
               c("codigo_municipio", "ano", "variavel_codigo", "unidade", "valor")]
if (anyNA(longo$codigo_municipio) || anyNA(longo$ano)) stop("Codigo municipal ou ano invalido no bruto.")
faltantes <- setdiff(names(VARIAVEIS), unique(longo$variavel_codigo))
if (length(faltantes)) stop("Variaveis ausentes no bruto: ", paste(faltantes, collapse = ", "))
unidades <- unique(longo$unidade[!is.na(longo$valor)])
if (!identical(unidades, "Mil Reais")) stop("Unidade inesperada: ", paste(unidades, collapse = " | "))
if (any(longo$valor < 0, na.rm = TRUE)) stop("Ha valor monetario negativo no bruto.")
if (anyDuplicated(longo[c("codigo_municipio", "ano", "variavel_codigo")])) stop("Chave municipio-ano-variavel duplicada no bruto.")
log_msg(nrow(longo), " observacoes: ", sum(is.na(longo$valor)), " indisponiveis (NA) e ",
        sum(longo$valor == 0, na.rm = TRUE), " zeros absolutos.")

# 2. Formato largo: uma linha por municipio-ano
base <- unique(longo[c("codigo_municipio", "ano")])
chave <- paste(base$codigo_municipio, base$ano)
for (codigo in names(VARIAVEIS)) {
  parte <- longo[longo$variavel_codigo == codigo, ]
  base[[VARIAVEIS[[codigo]]]] <- parte$valor[match(chave, paste(parte$codigo_municipio, parte$ano))]
}
# Municipio-ano sem nenhum valor (municipio ainda nao instalado) sai da base.
sem_dados <- rowSums(!is.na(base[unname(VARIAVEIS)])) == 0L
if (any(sem_dados)) log_msg(sum(sem_dados), " municipio-ano sem nenhum valor descartados.")
base <- base[!sem_dados, ]
chave <- paste(base$codigo_municipio, base$ano)

# 3. Consistencia contabil (apenas aviso): VAB = soma dos setores; PIB = VAB + impostos
dif_vab <- with(base, vab_total - (vab_agropecuaria + vab_industria + vab_servicos + vab_adm_publica))
dif_pib <- with(base, pib - (vab_total + impostos_liquidos))
n_divergentes <- sum(abs(dif_vab) > TOLERANCIA_IDENTIDADE, na.rm = TRUE) +
  sum(abs(dif_pib) > TOLERANCIA_IDENTIDADE, na.rm = TRUE)
if (n_divergentes) log_msg("Aviso: ", n_divergentes, " municipio-ano com diferenca acima de ",
                           TOLERANCIA_IDENTIDADE, " mil reais nas identidades contabeis.")

# 4. PIB per capita: populacao do Ipeadata, POPTOT (censos e contagens) quando
#    existir e ESTIMA_PO (estimativas anuais) nos demais anos. Anos sem
#    populacao publicada ficam NA.
ler_populacao <- function(serie) {
  pop <- as.data.frame(ler_csv(exigir_bruto(paste0("ipeadata_", serie, ".csv"))))
  pop$codigo_municipio <- padronizar_codigo7(pop$codigo_municipio)
  pop <- pop[!is.na(pop$codigo_municipio) & !is.na(pop$valor), c("codigo_municipio", "ano", "valor")]
  if (anyDuplicated(pop[c("codigo_municipio", "ano")])) stop("Municipio-ano duplicado na serie ", serie, ".")
  pop
}
populacao <- rep(NA_real_, length(chave))
for (serie in c("POPTOT", "ESTIMA_PO")) {
  pop <- ler_populacao(serie)
  pendentes <- is.na(populacao)
  populacao[pendentes] <- pop$valor[match(chave[pendentes], paste(pop$codigo_municipio, pop$ano))]
}
base$pib_per_capita <- round(ifelse(!is.na(populacao) & populacao > 0, base$pib * 1000 / populacao, NA_real_), 2)
log_msg("PIB per capita calculado para ", sum(!is.na(base$pib_per_capita)), " de ", nrow(base),
        " municipio-ano; anos sem populacao: ",
        paste(sort(unique(base$ano[is.na(populacao)])), collapse = ", "))

# 5. Nome/UF oficiais e gravacao
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c(unname(VARIAVEIS), "pib_per_capita"),
  descricao = c(
    "Produto Interno Bruto a precos correntes (SIDRA 5938, variavel 37)",
    "Valor adicionado bruto total a precos correntes (variavel 498)",
    "Valor adicionado bruto da agropecuaria a precos correntes (variavel 513)",
    "Valor adicionado bruto da industria a precos correntes (variavel 517)",
    "Valor adicionado bruto dos servicos, exclusive administracao, defesa, educacao e saude publicas e seguridade social, a precos correntes (variavel 6575)",
    "Valor adicionado bruto da administracao, defesa, educacao e saude publicas e seguridade social, a precos correntes (variavel 525)",
    "Impostos, liquidos de subsidios, sobre produtos, a precos correntes (variavel 543)",
    "PIB a precos correntes dividido pela populacao residente do Ipeadata (POPTOT nos anos de censo/contagem, ESTIMA_PO nos demais); NA nos anos sem populacao publicada"
  ),
  unidade = c(rep("R$ mil correntes", length(VARIAVEIS)), "R$ correntes por habitante"),
  periodicidade = "anual",
  tabela = "SIDRA 5938",
  fonte_url = "https://sidra.ibge.gov.br/tabela/5938",
  stringsAsFactors = FALSE
))
