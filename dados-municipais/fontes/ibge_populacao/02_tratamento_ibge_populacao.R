# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_ibge_populacao.R
# FONTE: IBGE - populacao residente estimada (ESTIMA_PO) e total (POPTOT), via
#        API do Ipeadata
# OBJETIVO: Ler os brutos, manter apenas o nivel municipal, organizar as duas
#           series por municipio-ano e gravar a base municipal do painel.
# ENTRADAS: dados/brutos/ibge_populacao/ipeadata_ESTIMA_PO.csv
#           dados/brutos/ibge_populacao/ipeadata_POPTOT.csv
# SAIDAS: dados/tratados/ibge_populacao/ibge_populacao_municipal.csv
#         dados/tratados/ibge_populacao/ibge_populacao_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/ibge_populacao/02_tratamento_ibge_populacao.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "ibge_populacao"

dicionario <- carregar_dicionario_municipios()

ler_serie_municipal <- function(serie) {
  arquivo <- file.path(dir_brutos(FONTE), paste0("ipeadata_", serie, ".csv"))
  if (!file.exists(arquivo)) stop("Bruto nao encontrado: ", arquivo, ". Execute o script 01 antes.")
  bruto <- as.data.frame(ler_csv(arquivo, colunas_texto = "TERCODIGO"))
  # A API devolve varios niveis territoriais (Brasil, regioes, UFs, meso e
  # microrregioes, areas minimas comparaveis); somente o municipal entra.
  bruto <- bruto[remover_acentos(as.character(bruto$NIVNOME)) %in% c("Municipios", "Municipio"), , drop = FALSE]
  x <- data.frame(
    codigo_municipio = padronizar_codigo7(bruto$TERCODIGO),
    ano = as.integer(substr(as.character(bruto$VALDATA), 1L, 4L)),
    valor = suppressWarnings(as.numeric(bruto$VALVALOR)),
    stringsAsFactors = FALSE
  )
  # Recorte por UF somente para testes (PAINEL_UFS); o padrao e todo o Brasil.
  x <- x[!is.na(x$codigo_municipio) & uf_por_codigo(x$codigo_municipio) %in% UFS_ATIVAS$uf, , drop = FALSE]
  # Populacao zero ou negativa nao e informacao valida: vira NA (nunca zero).
  invalidos <- !is.na(x$valor) & x$valor <= 0
  if (any(invalidos)) log_msg("Aviso: ", sum(invalidos), " valor(es) nao positivo(s) em ", serie, " convertido(s) para NA.")
  x$valor[invalidos] <- NA_real_
  if (anyDuplicated(x[c("codigo_municipio", "ano")])) stop("Chave municipio-ano duplicada na serie ", serie, ".")
  log_msg(serie, ": ", nrow(x), " linhas municipais, ", length(unique(x$codigo_municipio)),
          " municipios, ", min(x$ano), "-", max(x$ano))
  x
}

# 1. Leitura das duas series (nivel municipal)
estimada <- ler_serie_municipal("ESTIMA_PO")
total <- ler_serie_municipal("POPTOT")
ANO_INICIAL <- ano_inicial_efetivo(min(c(estimada$ano, total$ano)))

# 2. Formato largo: uma linha por municipio-ano com as duas series lado a lado
chave <- function(df) paste(df$codigo_municipio, df$ano)
base <- unique(rbind(estimada[c("codigo_municipio", "ano")], total[c("codigo_municipio", "ano")]))
base <- base[base$ano >= ANO_INICIAL, , drop = FALSE]
base$populacao_estimada <- estimada$valor[match(chave(base), chave(estimada))]
base$populacao_total <- total$valor[match(chave(base), chave(total))]
# Populacao de referencia do ano: a populacao total do Censo/Contagem quando o
# ano e censitario; a estimativa de 1o de julho nos demais anos.
base$populacao <- ifelse(is.na(base$populacao_total), base$populacao_estimada, base$populacao_total)
base <- base[!is.na(base$populacao), , drop = FALSE]

# 3. Nome/UF oficiais (codigos de municipios extintos ou fora do dicionario
#    oficial sao descartados) e gravacao
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("populacao_estimada", "populacao_total", "populacao"),
  descricao = c(
    "Populacao residente estimada em 1o de julho (IBGE, serie ESTIMA_PO do Ipeadata)",
    "Populacao residente total apurada nos Censos Demograficos e na Contagem 2007 (IBGE, serie POPTOT do Ipeadata); vazia nos demais anos",
    "Populacao residente de referencia do ano: populacao_total no ano censitario e populacao_estimada nos demais anos"
  ),
  unidade = "habitantes",
  periodicidade = c("anual", "decenal (anos censitarios)", "anual"),
  tabela = c("ESTIMA_PO", "POPTOT", "ESTIMA_PO + POPTOT"),
  fonte_url = "https://www.ipeadata.gov.br/",
  stringsAsFactors = FALSE
))
