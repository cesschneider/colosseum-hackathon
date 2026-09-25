# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_sagicad_cadunico.R
# FONTE: SAGI/MDS - MISocial (Cadastro Unico) + Ipeadata (populacao)
# OBJETIVO: Ler o bruto consolidado, converter o codigo IBGE de 6 para 7 digitos,
#           padronizar pessoas/familias cadastradas por faixa de renda, calcular
#           a parcela da populacao no Cadastro Unico e gravar a base municipal
#           MENSAL do painel.
# ENTRADAS: dados/brutos/sagicad_cadunico/sagicad_cadunico_misocial_<inicio>_<fim>.csv
#           dados/brutos/sagicad_cadunico/ipeadata_populacao.csv
# SAIDAS: dados/tratados/sagicad_cadunico/sagicad_cadunico_municipal.csv
#         dados/tratados/sagicad_cadunico/sagicad_cadunico_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/sagicad_cadunico/02_tratamento_sagicad_cadunico.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "sagicad_cadunico"
URL_FONTE <- "https://aplicacoes.mds.gov.br/sagi/servicos/misocial/"
ANO_INICIAL <- ano_inicial_efetivo(2012L)

dicionario <- carregar_dicionario_municipios()
dir_entrada <- dir_brutos(FONTE)

# 1. Bruto consolidado: prefere o download com o mesmo inicio desta execucao;
#    senao, o mais recente disponivel.
arquivos <- list.files(dir_entrada, pattern = sprintf("_misocial_%d01_[0-9]{6}[.]csv$", ANO_INICIAL), full.names = TRUE)
if (!length(arquivos)) arquivos <- list.files(dir_entrada, pattern = "_misocial_[0-9]{6}_[0-9]{6}[.]csv$", full.names = TRUE)
if (!length(arquivos)) stop("Nenhum bruto encontrado. Execute o script 01 antes.")
arquivo <- arquivos[which.max(file.info(arquivos)$mtime)]
bruto <- as.data.frame(ler_csv(arquivo))
log_msg("Bruto: ", basename(arquivo), " (", nrow(bruto), " linhas)")

# 2. Chaves e indicadores da fonte (codigo IBGE 6 -> 7 digitos; aaaamm -> ano/mes).
#    Faixas de renda familiar per capita conforme as linhas vigentes em cada mes
#    (extrema pobreza < pobreza < meio salario minimo); os limites em reais
#    mudaram ao longo do tempo (ver README).
competencia <- as.integer(bruto$anomes_s)
bruto <- bruto[competencia %/% 100L >= ANO_INICIAL, ]
competencia <- competencia[competencia %/% 100L >= ANO_INICIAL]
base <- data.frame(
  codigo_municipio = codigo6_para_7(bruto$codigo_ibge, dicionario),
  ano = competencia %/% 100L,
  mes = competencia %% 100L,
  pessoas_cadastradas = para_numero(bruto$cadun_qtd_pessoas_cadastradas_i),
  familias_cadastradas = para_numero(bruto$cadun_qtd_familias_cadastradas_i),
  familias_extrema_pobreza = para_numero(bruto$cadun_qtde_fam_sit_extrema_pobreza_s),
  familias_pobreza = para_numero(bruto$cadun_qtde_fam_sit_pobreza_s),
  familias_ate_linha_pobreza = para_numero(bruto$cadun_qtd_familias_cadastradas_pobreza_pbf_i),
  pessoas_ate_linha_pobreza = para_numero(bruto$cadun_qtd_pessoas_cadastradas_pobreza_pbf_i),
  familias_baixa_renda = para_numero(bruto$cadun_qtd_familias_cadastradas_baixa_renda_i),
  familias_ate_meio_salario_minimo = para_numero(bruto$cadun_qtd_familias_cadastradas_rfpc_ate_meio_sm_i),
  stringsAsFactors = FALSE
)
fora <- is.na(base$codigo_municipio)
if (any(fora)) {
  log_msg("Aviso: ", sum(fora), " linha(s) com codigo IBGE fora do dicionario oficial descartada(s). Ex.: ",
          paste(head(unique(bruto$codigo_ibge[fora]), 5L), collapse = ", "))
  base <- base[!fora, ]
}

# 3. Populacao de referencia (Ipeadata): censo (POPTOT) quando existe, senao a
#    estimativa anual (ESTIMA_PO). Anos sem dado proprio (ex.: 2023 e os meses do
#    ano corrente antes da divulgacao das estimativas) recebem o ultimo ano
#    disponivel anterior.
juntar_populacao <- function(base) {
  arquivo_pop <- file.path(dir_entrada, "ipeadata_populacao.csv")
  pop <- if (file.exists(arquivo_pop)) as.data.frame(ler_csv(arquivo_pop)) else
    rbind(ipeadata_municipal("POPTOT"), ipeadata_municipal("ESTIMA_PO"))
  pop$codigo_municipio <- padronizar_codigo7(pop$codigo_municipio)
  pop <- pop[order(pop$serie != "POPTOT"), ]
  pop <- pop[!is.na(pop$valor) & !is.na(pop$codigo_municipio) & !duplicated(pop[c("codigo_municipio", "ano")]), ]
  anos_pop <- sort(unique(as.integer(pop$ano)))
  anos <- sort(unique(base$ano))
  ano_ref <- vapply(anos, function(a) {
    if (any(anos_pop <= a)) as.integer(max(anos_pop[anos_pop <= a])) else NA_integer_
  }, integer(1L))
  substitutos <- anos[!is.na(ano_ref) & ano_ref != anos]
  if (length(substitutos)) {
    log_msg("Populacao: anos sem dado proprio usam o ultimo ano disponivel: ",
            paste(paste0(substitutos, "<-", ano_ref[match(substitutos, anos)]), collapse = ", "))
  }
  ref <- ano_ref[match(base$ano, anos)]
  idx <- match(paste(base$codigo_municipio, ref), paste(pop$codigo_municipio, pop$ano))
  base$populacao_estimada <- as.numeric(pop$valor[idx])
  base
}
base <- juntar_populacao(base)
# A razao pode superar 100: o cadastro acumula pessoas e a populacao e uma
# estimativa com outra data de referencia. Nao se trunca (regra do original).
base$pct_populacao_cadastrada <- 100 * base$pessoas_cadastradas / base$populacao_estimada

# 4. Nome/UF oficiais e gravacao (chave municipio-ano-mes validada na gravacao)
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base, mensal = TRUE)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("pessoas_cadastradas", "familias_cadastradas", "familias_extrema_pobreza",
               "familias_pobreza", "familias_ate_linha_pobreza", "pessoas_ate_linha_pobreza",
               "familias_baixa_renda", "familias_ate_meio_salario_minimo", "populacao_estimada",
               "pct_populacao_cadastrada"),
  descricao = c(
    "Pessoas cadastradas no Cadastro Unico no mes (MISocial: cadun_qtd_pessoas_cadastradas_i)",
    "Familias cadastradas no Cadastro Unico no mes (MISocial: cadun_qtd_familias_cadastradas_i)",
    "Familias cadastradas em situacao de extrema pobreza (renda familiar per capita ate a linha de extrema pobreza vigente; MISocial: cadun_qtde_fam_sit_extrema_pobreza_s)",
    "Familias cadastradas em situacao de pobreza (renda familiar per capita entre a linha de extrema pobreza e a linha de pobreza vigentes; MISocial: cadun_qtde_fam_sit_pobreza_s)",
    "Familias cadastradas com renda familiar per capita ate a linha de pobreza do Bolsa Familia (extrema pobreza + pobreza; MISocial: cadun_qtd_familias_cadastradas_pobreza_pbf_i)",
    "Pessoas cadastradas com renda familiar per capita ate a linha de pobreza do Bolsa Familia (MISocial: cadun_qtd_pessoas_cadastradas_pobreza_pbf_i)",
    "Familias cadastradas de baixa renda (renda familiar per capita entre a linha de pobreza e meio salario minimo; MISocial: cadun_qtd_familias_cadastradas_baixa_renda_i)",
    "Familias cadastradas com renda familiar per capita ate meio salario minimo (MISocial: cadun_qtd_familias_cadastradas_rfpc_ate_meio_sm_i)",
    "Populacao residente de referencia do ano (Ipeadata: censo POPTOT ou estimativa ESTIMA_PO; ultimo ano disponivel quando o ano nao tem dado)",
    "Parcela da populacao inscrita no Cadastro Unico (100 * pessoas_cadastradas / populacao_estimada); pode superar 100"
  ),
  unidade = c("pessoas", "familias", "familias", "familias", "familias", "pessoas", "familias",
              "familias", "habitantes", "% da populacao"),
  periodicidade = "mensal",
  tabela = "MISocial (SAGI/MDS)",
  fonte_url = URL_FONTE,
  stringsAsFactors = FALSE
))
