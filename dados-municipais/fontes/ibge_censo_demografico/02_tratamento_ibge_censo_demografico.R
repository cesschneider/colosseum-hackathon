# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_ibge_censo_demografico.R
# FONTE: IBGE - Censos Demograficos 2000, 2010 e 2022 (tabelas SIDRA 1552 e 9514)
# OBJETIVO: Ler os brutos, agregar as categorias de idade nas faixas etarias do
#           painel e nos grandes grupos, abrir a populacao por sexo e calcular
#           os indicadores de estrutura etaria (uma linha por municipio-ano).
# ENTRADAS: dados/brutos/ibge_censo_demografico/sidra_<tabela>_<ano>_<idade|sexo>.rds
# SAIDAS: dados/tratados/ibge_censo_demografico/ibge_censo_demografico_municipal.csv
#         dados/tratados/ibge_censo_demografico/ibge_censo_demografico_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/ibge_censo_demografico/02_tratamento_ibge_censo_demografico.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "ibge_censo_demografico"

PLANO <- data.frame(tabela = c(1552L, 1552L, 1552L, 1552L, 9514L, 9514L),
                    ano = c(2000L, 2000L, 2010L, 2010L, 2022L, 2022L),
                    tipo = rep(c("idade", "sexo"), 3L), stringsAsFactors = FALSE)
PLANO <- PLANO[PLANO$ano >= ano_inicial_efetivo(2000L), ]
# Categorias de idade (c287) -> faixas etarias do painel e grandes grupos.
# As tabelas usam grupos finais diferentes (1552: 80-89 e 90-99; 9514: 80-84,
# 85-89, 90-94 e 95-99), todos dentro de "60 ou mais" e "65 ou mais".
IDADES <- data.frame(
  codigo = c("93070", "93084", "93085", "93086", "93087", "93088", "93089", "93090",
             "93091", "93092", "93093", "93094", "93095", "93096", "93097", "93098",
             "93099", "93100", "49108", "49109", "60040", "60041", "6653"),
  faixa = c("pop_0_a_4", "pop_5_a_9", "pop_10_a_19", "pop_10_a_19", "pop_20_a_29",
            "pop_20_a_29", "pop_30_a_39", "pop_30_a_39", "pop_40_a_49", "pop_40_a_49",
            "pop_50_a_59", "pop_50_a_59", rep("pop_60_mais", 11L)),
  grupo = c(rep("pop_0_a_14", 3L), rep("pop_15_a_64", 10L), rep("pop_65_mais", 10L)),
  stringsAsFactors = FALSE
)
SEXOS <- data.frame(tabela = c(1552L, 1552L, 9514L, 9514L), codigo = c("92956", "92957", "4", "5"),
                    sexo = c("pop_homens", "pop_mulheres", "pop_homens", "pop_mulheres"),
                    stringsAsFactors = FALSE)
FAIXAS <- unique(IDADES$faixa)
GRUPOS <- unique(IDADES$grupo)
MEDIDAS <- c(FAIXAS, GRUPOS, "pop_homens", "pop_mulheres")
dir_entrada <- dir_brutos(FONTE)
dicionario <- carregar_dicionario_municipios()

# Soma que preserva NA quando todos os componentes estao indisponiveis
# (indisponibilidade no Censo nao significa populacao zero).
somar_preservando_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

# 1. Leitura dos brutos: codigo do municipio, codigos de sexo e idade e valor
ler_bruto <- function(i) {
  arquivo <- file.path(dir_entrada, sprintf("sidra_%d_%d_%s.rds", PLANO$tabela[i], PLANO$ano[i], PLANO$tipo[i]))
  if (!file.exists(arquivo)) stop("Bruto nao encontrado (execute o script 01 antes): ", arquivo)
  bruto <- readRDS(arquivo)
  pad <- sidra_padronizar(bruto)
  # Convencao do SIDRA: "-" e zero absoluto; "...", ".." e "X" ficam NA.
  pad$valor[trimws(as.character(bruto[["Valor"]])) == "-"] <- 0
  coluna_codigo <- function(prefixo) {
    nome <- names(pad)[remover_acentos(names(pad)) == paste0(prefixo, " (Codigo)")]
    if (!length(nome)) stop("Coluna '", prefixo, " (Codigo)' ausente em ", basename(arquivo))
    trimws(as.character(pad[[nome[[1L]]]]))
  }
  data.frame(tabela = PLANO$tabela[i], ano = PLANO$ano[i], tipo = PLANO$tipo[i],
             codigo_municipio = pad$codigo_municipio, codigo_sexo = coluna_codigo("Sexo"),
             codigo_idade = coluna_codigo("Idade"), unidade = pad$unidade, valor = pad$valor,
             stringsAsFactors = FALSE)
}
bruto <- do.call(rbind, lapply(seq_len(nrow(PLANO)), ler_bruto))
if (anyNA(bruto$codigo_municipio)) stop("Codigo municipal invalido no bruto.")
unidades <- unique(bruto$unidade[!is.na(bruto$valor)])
if (!identical(unidades, "Pessoas")) stop("Unidade inesperada: ", paste(unidades, collapse = " | "))
if (any(bruto$valor < 0, na.rm = TRUE)) stop("Ha contagem populacional negativa no bruto.")
if (anyDuplicated(bruto[c("tabela", "tipo", "ano", "codigo_municipio", "codigo_sexo", "codigo_idade")])) {
  stop("Chave tabela-tipo-ano-municipio-sexo-idade duplicada no bruto.")
}

# Formato largo com uma coluna por categoria agregada (NA quando indisponivel)
para_largo <- function(df, coluna) {
  m <- tapply(df$valor, list(paste(df$codigo_municipio, df$ano), df[[coluna]]), somar_preservando_na)
  saida <- data.frame(chave = rownames(m), as.data.frame(unclass(m)), check.names = FALSE, stringsAsFactors = FALSE)
  rownames(saida) <- NULL
  saida
}

# 2. Idade: agregacao nas faixas do painel e nos grandes grupos
idade <- bruto[bruto$tipo == "idade", ]
idade$faixa <- IDADES$faixa[match(idade$codigo_idade, IDADES$codigo)]
idade$grupo <- IDADES$grupo[match(idade$codigo_idade, IDADES$codigo)]
if (anyNA(idade$faixa)) stop("Categoria de idade sem regra de agregacao: ",
                             paste(unique(idade$codigo_idade[is.na(idade$faixa)]), collapse = ", "))
# Cada municipio-ano precisa trazer todas as categorias da sua tabela; do
# contrario a soma das faixas ficaria subestimada.
chave_idade <- paste(idade$codigo_municipio, idade$ano)
n_categorias <- tapply(idade$codigo_idade, idade$tabela, function(x) length(unique(x)))
n_por_chave <- table(chave_idade)
tabela_por_chave <- idade$tabela[match(names(n_por_chave), chave_idade)]
if (any(as.integer(n_por_chave) != n_categorias[as.character(tabela_por_chave)])) {
  stop("Ha municipio-ano com categorias de idade incompletas no bruto.")
}
faixas <- para_largo(idade, "faixa")
grupos <- para_largo(idade, "grupo")

# 3. Sexo: codigos distintos por tabela, mesmo significado
sexo <- bruto[bruto$tipo == "sexo", ]
sexo$sexo <- SEXOS$sexo[match(paste(sexo$tabela, sexo$codigo_sexo), paste(SEXOS$tabela, SEXOS$codigo))]
if (anyNA(sexo$sexo)) stop("Categoria de sexo inesperada: ",
                           paste(unique(paste(sexo$tabela, sexo$codigo_sexo)[is.na(sexo$sexo)]), collapse = ", "))
sexos <- para_largo(sexo, "sexo")

# 4. Painel municipio-ano e indicadores
base <- merge(merge(faixas, grupos, by = "chave", all = TRUE), sexos, by = "chave", all = TRUE)
for (v in setdiff(MEDIDAS, names(base))) base[[v]] <- NA_real_
base$codigo_municipio <- substr(base$chave, 1L, 7L)
base$ano <- as.integer(substr(base$chave, 9L, 12L))
base$chave <- NULL
# Municipio-ano sem nenhuma medida (municipio instalado depois do Censo) sai da base.
sem_dados <- rowSums(!is.na(base[MEDIDAS])) == 0L
if (any(sem_dados)) log_msg(sum(sem_dados), " municipio-ano sem nenhum valor descartados.")
base <- base[!sem_dados, ]

base$populacao_total <- apply(base[c("pop_homens", "pop_mulheres")], 1L, somar_preservando_na)
total_faixas <- apply(base[FAIXAS], 1L, somar_preservando_na)
divergentes <- sum(!is.na(total_faixas) & !is.na(base$populacao_total) & total_faixas != base$populacao_total)
if (divergentes) log_msg("Aviso: ", divergentes, " municipio-ano em que a soma das faixas etarias difere de homens + mulheres.")

razao <- function(numerador, denominador) {
  round(ifelse(!is.na(denominador) & denominador > 0, numerador / denominador * 100, NA_real_), 2)
}
base$razao_dependencia_jovem <- razao(base$pop_0_a_14, base$pop_15_a_64)
base$razao_dependencia_idosa <- razao(base$pop_65_mais, base$pop_15_a_64)
base$razao_dependencia_total <- razao(base$pop_0_a_14 + base$pop_65_mais, base$pop_15_a_64)
base$indice_envelhecimento <- razao(base$pop_65_mais, base$pop_0_a_14)
base$razao_sexo <- razao(base$pop_homens, base$pop_mulheres)

# 5. Nome/UF oficiais e gravacao
base <- base[c("codigo_municipio", "ano", "populacao_total", "pop_homens", "pop_mulheres", FAIXAS, GRUPOS,
               "razao_dependencia_jovem", "razao_dependencia_idosa", "razao_dependencia_total",
               "indice_envelhecimento", "razao_sexo")]
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("populacao_total", "pop_homens", "pop_mulheres", FAIXAS, GRUPOS,
               "razao_dependencia_jovem", "razao_dependencia_idosa", "razao_dependencia_total",
               "indice_envelhecimento", "razao_sexo"),
  descricao = c(
    "Populacao residente total (homens + mulheres)",
    "Populacao residente masculina",
    "Populacao residente feminina",
    "Populacao residente de 0 a 4 anos",
    "Populacao residente de 5 a 9 anos",
    "Populacao residente de 10 a 19 anos",
    "Populacao residente de 20 a 29 anos",
    "Populacao residente de 30 a 39 anos",
    "Populacao residente de 40 a 49 anos",
    "Populacao residente de 50 a 59 anos",
    "Populacao residente de 60 anos ou mais",
    "Populacao residente de 0 a 14 anos",
    "Populacao residente de 15 a 64 anos",
    "Populacao residente de 65 anos ou mais",
    "Razao de dependencia jovem: populacao de 0 a 14 anos por 100 pessoas de 15 a 64 anos",
    "Razao de dependencia idosa: populacao de 65 anos ou mais por 100 pessoas de 15 a 64 anos",
    "Razao de dependencia total: populacao de 0 a 14 e de 65 anos ou mais por 100 pessoas de 15 a 64 anos",
    "Indice de envelhecimento: populacao de 65 anos ou mais por 100 pessoas de 0 a 14 anos",
    "Razao de sexo: homens por 100 mulheres"
  ),
  unidade = c(rep("pessoas", 3L + length(FAIXAS) + length(GRUPOS)), rep("por 100", 5L)),
  periodicidade = "decenal",
  tabela = "SIDRA 1552 (2000, 2010) e 9514 (2022)",
  fonte_url = "https://sidra.ibge.gov.br/tabela/9514",
  stringsAsFactors = FALSE
))
