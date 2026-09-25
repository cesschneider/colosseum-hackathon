# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_mapbiomas.R
# FONTE: MapBiomas Brasil - Estatisticas de cobertura e uso da terra (colecao vigente)
# OBJETIVO: Ler a planilha municipal (aba COVERAGE_<colecao>), somar a area em
#           hectares por municipio-ano para as classes de nivel 1 e para alguns
#           subniveis de interesse (pastagem, agricultura, area urbana...) e
#           gravar a base municipal no esquema do painel.
# ENTRADAS: dados/brutos/mapbiomas/mapbiomas_cobertura_municipios_col<colecao>.xlsx
# SAIDAS: dados/tratados/mapbiomas/mapbiomas_municipal.csv
#         dados/tratados/mapbiomas/mapbiomas_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/mapbiomas/02_tratamento_mapbiomas.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table", "readxl"))
library(data.table)
FONTE <- "mapbiomas"

ANO_INICIAL <- ano_inicial_efetivo(1985L)
dicionario <- carregar_dicionario_municipios()

# 1. Bruto da colecao mais recente disponivel em dados/brutos/mapbiomas
arquivos <- list.files(dir_brutos(FONTE), pattern = "^mapbiomas_cobertura_municipios_col.*[.]xlsx$", full.names = TRUE)
if (!length(arquivos)) stop("Nenhum bruto encontrado. Execute o script 01 antes.")
colecoes <- suppressWarnings(as.numeric(sub("^.*_col([0-9.]+)[.]xlsx$", "\\1", basename(arquivos))))
bruto <- arquivos[which.max(ifelse(is.na(colecoes), -Inf, colecoes))]
abas <- readxl::excel_sheets(bruto)
aba <- grep("^COVERAGE_", abas, value = TRUE)
if (length(aba) != 1L) stop("Esperada uma aba COVERAGE_*; encontradas: ", paste(abas, collapse = ", "))
colecao <- sub("^COVERAGE_", "", aba)
log_msg("Lendo ", basename(bruto), ", aba ", aba, " (a planilha nacional leva alguns minutos).")
dados <- as.data.table(readxl::read_excel(bruto, sheet = aba, guess_max = 10000L))

# 2. Colunas: anos (uma coluna por ano), classes por nivel e codigo IBGE
nomes <- names(dados)
colunas_ano <- nomes[grepl("^y?[0-9]{4}$", nomes)]
colunas_ano <- colunas_ano[as.integer(sub("^y", "", colunas_ano)) >= ANO_INICIAL]
faltantes <- setdiff(c("class_level_1", "class_level_2"), nomes)
if (length(faltantes) || !length(colunas_ano)) {
  stop("Esquema inesperado na aba ", aba, ": faltam ",
       paste(c(faltantes, if (!length(colunas_ano)) "colunas de ano"), collapse = ", "))
}
if ("geocode" %in% nomes) {
  dados[, codigo_municipio := padronizar_codigo7(geocode)]
} else {
  # Colecoes sem geocode: junta por nome + UF (sigla ou nome do estado).
  col_uf <- intersect(c("state_acronym", "state"), nomes)
  if (!"municipality" %in% nomes || !length(col_uf)) stop("Sem geocode nem municipality/state na aba ", aba)
  dados[, uf_sigla := if (col_uf[1L] == "state_acronym") toupper(state_acronym) else
    UFS$uf[match(normalizar_nome(state), normalizar_nome(UFS$nome_uf))]]
  dados <- as.data.table(juntar_por_nome_uf(dados, "municipality", "uf_sigla", dicionario))
}
sem_codigo <- sum(is.na(dados$codigo_municipio))
if (sem_codigo) log_msg("Aviso: ", sem_codigo, " linha(s) sem codigo IBGE reconhecido descartadas.")
dados <- dados[!is.na(codigo_municipio)]

# 3. Mapeamento das classes. Os rotulos da planilha estao em ingles e a
#    numeracao/grafia muda entre colecoes ("2. Non Forest Natural Formation" ou
#    "2. Herbaceous and Shrubby Vegetation"; "5. Water" ou "5. Water and Marine
#    Environment"; "6." ou "7. Not Observed"); por isso o casamento e por
#    palavra-chave. Cada linha da planilha e uma classe folha, entao a soma por
#    nivel 1 nao conta area duas vezes.
classe_nivel1 <- function(x) {
  x <- tolower(remover_acentos(as.character(x)))
  fcase(
    grepl("non forest|natural formation|herbaceous|shrubby", x), "area_formacao_natural_nao_florestal_ha",
    grepl("forest", x), "area_floresta_ha",
    grepl("farming|agropec", x), "area_agropecuaria_ha",
    grepl("non vegetated|non-vegetated", x), "area_nao_vegetada_ha",
    grepl("water", x), "area_agua_ha",
    grepl("not observed", x), "area_nao_observada_ha",
    default = NA_character_
  )
}
classe_nivel2 <- function(x) {
  x <- tolower(remover_acentos(as.character(x)))
  fcase(
    grepl("pasture", x), "area_pastagem_ha",
    grepl("agriculture", x), "area_agricultura_ha",
    grepl("forest plantation|silvicult", x), "area_silvicultura_ha",
    grepl("mosaic", x), "area_mosaico_de_usos_ha",
    grepl("urban", x), "area_urbana_ha",
    grepl("mining", x), "area_mineracao_ha",
    default = NA_character_
  )
}
dados[, variavel_n1 := classe_nivel1(class_level_1)]
dados[, variavel_n2 := classe_nivel2(class_level_2)]
nao_mapeadas <- unique(dados[is.na(variavel_n1), class_level_1])
if (length(nao_mapeadas)) stop("Classes de nivel 1 sem mapeamento: ", paste(nao_mapeadas, collapse = ", "))

# 4. Agregacao municipio-ano. Ausencia nao e zero: se todas as parcelas de um
#    grupo estiverem vazias o agregado fica NA; classe sem linha para o
#    municipio (planilha esparsa) e zero estrutural (fill = 0 no dcast).
soma_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
dados[, (colunas_ano) := lapply(.SD, function(x) suppressWarnings(as.numeric(x))), .SDcols = colunas_ano]
agregada <- rbind(
  dados[, lapply(.SD, soma_na), by = .(codigo_municipio, variavel = variavel_n1), .SDcols = colunas_ano],
  dados[!is.na(variavel_n2), lapply(.SD, soma_na), by = .(codigo_municipio, variavel = variavel_n2), .SDcols = colunas_ano]
)
longa <- melt(agregada, id.vars = c("codigo_municipio", "variavel"), variable.name = "ano",
              value.name = "area_ha", variable.factor = FALSE)
longa[, ano := as.integer(sub("^y", "", ano))]
base <- dcast(longa, codigo_municipio + ano ~ variavel, value.var = "area_ha", fill = 0)

VARS_N1 <- c("area_floresta_ha", "area_formacao_natural_nao_florestal_ha", "area_agropecuaria_ha",
             "area_nao_vegetada_ha", "area_agua_ha", "area_nao_observada_ha")
VARS_N2 <- c("area_pastagem_ha", "area_agricultura_ha", "area_silvicultura_ha",
             "area_mosaico_de_usos_ha", "area_urbana_ha", "area_mineracao_ha")
ausentes <- setdiff(c(VARS_N1, VARS_N2), names(base))
if (length(ausentes)) {
  log_msg("Aviso: classes nao encontradas nesta colecao (ficam NA): ", paste(ausentes, collapse = ", "))
  for (v in ausentes) base[, (v) := NA_real_]
}
# Area total = soma das classes de nivel 1 (mutuamente exclusivas); NA se
# alguma parcela publicada estiver vazia.
base[, area_total_ha := rowSums(.SD), .SDcols = setdiff(VARS_N1, ausentes)]
setcolorder(base, c("codigo_municipio", "ano", VARS_N1, VARS_N2, "area_total_ha"))

# 5. Nome/UF oficiais e gravacao
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

descricoes <- c(
  area_floresta_ha = "Floresta (nivel 1: formacao florestal, savanica, mangue, restinga arborea, etc.)",
  area_formacao_natural_nao_florestal_ha = "Formacao natural nao florestal (nivel 1: campo, area umida, apicum, afloramento rochoso, etc.)",
  area_agropecuaria_ha = "Agropecuaria (nivel 1: pastagem + agricultura + silvicultura + mosaico de usos)",
  area_nao_vegetada_ha = "Area nao vegetada (nivel 1: praia/duna, area urbana, mineracao, outras)",
  area_agua_ha = "Corpos d'agua (nivel 1: rio, lago, oceano, aquicultura)",
  area_nao_observada_ha = "Nao observado (nivel 1)",
  area_pastagem_ha = "Pastagem (subclasse 3.1 da agropecuaria)",
  area_agricultura_ha = "Agricultura (subclasse 3.2: lavouras temporarias e perenes)",
  area_silvicultura_ha = "Silvicultura (subclasse 3.3: plantacao florestal)",
  area_mosaico_de_usos_ha = "Mosaico de usos (subclasse 3.4)",
  area_urbana_ha = "Area urbanizada (subclasse 4.2 da area nao vegetada)",
  area_mineracao_ha = "Mineracao (subclasse 4.3 da area nao vegetada)",
  area_total_ha = "Area total mapeada do municipio = soma das seis classes de nivel 1"
)
salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = names(descricoes),
  descricao = paste0(descricoes, " - MapBiomas Brasil, Colecao ", colecao),
  unidade = "hectares",
  periodicidade = "anual",
  tabela = aba,
  fonte_url = "https://brasil.mapbiomas.org/estatisticas/",
  stringsAsFactors = FALSE
))
