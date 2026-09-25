# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_sagicad_bolsa_familia.R
# FONTE: SAGI/MDS - MISocial (Bolsa Familia / Auxilio Brasil) + Ipeadata (populacao)
# OBJETIVO: Ler o bruto consolidado, converter o codigo IBGE de 6 para 7 digitos,
#           montar a serie continua do programa vigente (Bolsa Familia; Auxilio
#           Brasil entre nov/2021 e fev/2023), calcular beneficio medio, cobertura
#           e valor per capita e gravar a base municipal MENSAL do painel.
# ENTRADAS: dados/brutos/sagicad_bolsa_familia/sagicad_bolsa_familia_misocial_<inicio>_<fim>.csv
#           dados/brutos/sagicad_bolsa_familia/ipeadata_populacao.csv
# SAIDAS: dados/tratados/sagicad_bolsa_familia/sagicad_bolsa_familia_municipal.csv
#         dados/tratados/sagicad_bolsa_familia/sagicad_bolsa_familia_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/sagicad_bolsa_familia/02_tratamento_sagicad_bolsa_familia.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "sagicad_bolsa_familia"
URL_FONTE <- "https://aplicacoes.mds.gov.br/sagi/servicos/misocial/"
ANO_INICIAL <- ano_inicial_efetivo(2004L)

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

# 2. Chaves: codigo IBGE de 6 digitos -> 7 digitos; competencia aaaamm -> ano/mes
competencia <- as.integer(bruto$anomes_s)
bruto <- bruto[competencia %/% 100L >= ANO_INICIAL, ]
competencia <- competencia[competencia %/% 100L >= ANO_INICIAL]
base <- data.frame(
  codigo_municipio = codigo6_para_7(bruto$codigo_ibge, dicionario),
  ano = competencia %/% 100L,
  mes = competencia %% 100L,
  familias_bolsa_familia = para_numero(bruto$qtd_familias_beneficiarias_bolsa_familia),
  valor_bolsa_familia = para_numero(bruto$valor_repassado_bolsa_familia),
  familias_auxilio_brasil = para_numero(bruto$pab_qtd_fam_benef_i),
  valor_auxilio_brasil = para_numero(bruto$pab_valor_pago_d),
  stringsAsFactors = FALSE
)
fora <- is.na(base$codigo_municipio)
if (any(fora)) {
  log_msg("Aviso: ", sum(fora), " linha(s) com codigo IBGE fora do dicionario oficial descartada(s). Ex.: ",
          paste(head(unique(bruto$codigo_ibge[fora]), 5L), collapse = ", "))
  base <- base[!fora, ]
}

# 3. Serie continua do programa federal vigente: Bolsa Familia ate out/2021 e a
#    partir de mar/2023; Auxilio Brasil de nov/2021 a fev/2023. Se um mes tiver
#    os dois programas, prevalece o Bolsa Familia.
usa_pab <- is.na(base$familias_bolsa_familia) & !is.na(base$familias_auxilio_brasil)
base$familias_beneficiarias <- ifelse(usa_pab, base$familias_auxilio_brasil, base$familias_bolsa_familia)
base$valor_repassado <- ifelse(usa_pab, base$valor_auxilio_brasil, base$valor_bolsa_familia)
base$valor_medio_familia <- ifelse(base$familias_beneficiarias > 0,
                                   base$valor_repassado / base$familias_beneficiarias, NA_real_)

# 4. Populacao de referencia (Ipeadata): censo (POPTOT) quando existe, senao a
#    estimativa anual (ESTIMA_PO). Anos sem dado proprio (ex.: 2007, 2023 e os
#    meses do ano corrente antes da divulgacao das estimativas) recebem o ultimo
#    ano disponivel anterior.
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
base$familias_por_100_habitantes <- 100 * base$familias_beneficiarias / base$populacao_estimada
base$valor_repassado_per_capita <- base$valor_repassado / base$populacao_estimada

# 5. Nome/UF oficiais e gravacao (chave municipio-ano-mes validada na gravacao)
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base, mensal = TRUE)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("familias_bolsa_familia", "valor_bolsa_familia", "familias_auxilio_brasil",
               "valor_auxilio_brasil", "familias_beneficiarias", "valor_repassado",
               "valor_medio_familia", "populacao_estimada", "familias_por_100_habitantes",
               "valor_repassado_per_capita"),
  descricao = c(
    "Familias beneficiarias do Programa Bolsa Familia na folha de pagamento do mes (MISocial: qtd_familias_beneficiarias_bolsa_familia; ausente de nov/2021 a fev/2023)",
    "Valor total repassado pelo Programa Bolsa Familia no mes (MISocial: valor_repassado_bolsa_familia)",
    "Familias beneficiarias do Auxilio Brasil no mes (MISocial: pab_qtd_fam_benef_i; apenas nov/2021 a fev/2023)",
    "Valor total pago pelo Auxilio Brasil no mes (MISocial: pab_valor_pago_d; apenas nov/2021 a fev/2023)",
    "Familias beneficiarias do programa federal de transferencia de renda vigente no mes (Bolsa Familia; Auxilio Brasil entre nov/2021 e fev/2023)",
    "Valor total repassado no mes pelo programa vigente (Bolsa Familia; Auxilio Brasil entre nov/2021 e fev/2023), em reais correntes",
    "Valor medio repassado por familia beneficiaria no mes (valor_repassado / familias_beneficiarias)",
    "Populacao residente de referencia do ano (Ipeadata: censo POPTOT ou estimativa ESTIMA_PO; ultimo ano disponivel quando o ano nao tem dado)",
    "Cobertura: familias beneficiarias por 100 habitantes (100 * familias_beneficiarias / populacao_estimada)",
    "Valor repassado no mes por habitante (valor_repassado / populacao_estimada)"
  ),
  unidade = c("familias", "R$ correntes", "familias", "R$ correntes", "familias", "R$ correntes",
              "R$ correntes por familia", "habitantes", "familias por 100 habitantes",
              "R$ correntes por habitante"),
  periodicidade = "mensal",
  tabela = "MISocial (SAGI/MDS)",
  fonte_url = URL_FONTE,
  stringsAsFactors = FALSE
))
