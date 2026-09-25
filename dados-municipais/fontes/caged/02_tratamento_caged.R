# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_caged.R
# FONTE: MTE - Novo Caged via API do Ipeadata (ADMISNC e DESLIGNC)
# OBJETIVO: Ler os brutos, manter o nivel municipal, juntar admitidos e
#           desligados por municipio-mes, calcular o saldo e gravar a base
#           mensal e a base anual do painel.
# ENTRADAS: dados/brutos/caged/ipeadata_ADMISNC.csv
#           dados/brutos/caged/ipeadata_DESLIGNC.csv
# SAIDAS: dados/tratados/caged/caged_municipal.csv            (municipio-mes)
#         dados/tratados/caged/caged_anual_municipal.csv      (municipio-ano)
#         dados/tratados/caged/caged_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/caged/02_tratamento_caged.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "caged"

dicionario <- carregar_dicionario_municipios()
ANO_INICIAL <- ano_inicial_efetivo(2020L)   # inicio do Novo Caged na API

ler_serie_mensal <- function(serie) {
  arquivo <- file.path(dir_brutos(FONTE), paste0("ipeadata_", serie, ".csv"))
  if (!file.exists(arquivo)) stop("Bruto nao encontrado: ", arquivo, ". Execute o script 01 antes.")
  bruto <- as.data.frame(ler_csv(arquivo, colunas_texto = "TERCODIGO"))
  # Somente o nivel municipal entra (a API tambem devolve Brasil, regioes, UFs...).
  bruto <- bruto[remover_acentos(as.character(bruto$NIVNOME)) %in% c("Municipios", "Municipio"), , drop = FALSE]
  data <- as.character(bruto$VALDATA)
  x <- data.frame(
    codigo_municipio = padronizar_codigo7(bruto$TERCODIGO),
    ano = as.integer(substr(data, 1L, 4L)),
    mes = as.integer(substr(data, 6L, 7L)),
    valor = suppressWarnings(as.numeric(bruto$VALVALOR)),
    stringsAsFactors = FALSE
  )
  # Recorte por UF somente para testes (PAINEL_UFS); o padrao e todo o Brasil.
  x <- x[!is.na(x$codigo_municipio) & uf_por_codigo(x$codigo_municipio) %in% UFS_ATIVAS$uf &
           x$ano >= ANO_INICIAL, , drop = FALSE]
  # Sao contagens de movimentacoes: valor negativo indica mudanca de semantica
  # da serie na API e interrompe o tratamento.
  if (any(x$valor < 0, na.rm = TRUE)) stop("Valores negativos na serie ", serie, ".")
  if (anyDuplicated(x[c("codigo_municipio", "ano", "mes")])) stop("Chave municipio-competencia duplicada na serie ", serie, ".")
  log_msg(serie, ": ", nrow(x), " linhas municipais, ", length(unique(x$codigo_municipio)), " municipios, ",
          sprintf("%d-%02d", min(x$ano), min(x$mes[x$ano == min(x$ano)])), " a ",
          sprintf("%d-%02d", max(x$ano), max(x$mes[x$ano == max(x$ano)])))
  x
}

# 1. Leitura das duas series
admitidos <- ler_serie_mensal("ADMISNC")
desligados <- ler_serie_mensal("DESLIGNC")

# 2. Juncao externa por municipio-mes. A ausencia de uma competencia em uma das
#    series NAO e zero: fica NA, e o saldo so existe quando as duas existem.
chave <- function(df) paste(df$codigo_municipio, df$ano, df$mes)
base <- unique(rbind(admitidos[c("codigo_municipio", "ano", "mes")], desligados[c("codigo_municipio", "ano", "mes")]))
base$admitidos <- admitidos$valor[match(chave(base), chave(admitidos))]
base$desligados <- desligados$valor[match(chave(base), chave(desligados))]
base$saldo <- base$admitidos - base$desligados

# Competencias com menos municipios que o maximo observado (a mais recente
# costuma ser revisada nas divulgacoes seguintes): apenas registradas, sem imputar.
competencia <- sprintf("%d-%02d", base$ano, base$mes)
n_por_competencia <- tapply(!is.na(base$saldo), competencia, sum)
incompletas <- n_por_competencia[n_por_competencia < max(n_por_competencia)]
if (length(incompletas)) {
  log_msg("Aviso: ", length(incompletas), " competencia(s) com menos municipios que o maximo (",
          max(n_por_competencia), "): ",
          paste0(head(names(incompletas), 12L), " (", head(incompletas, 12L), ")", collapse = ", "))
}

# 3. Base anual: totais do ano somando apenas os meses em que admitidos e
#    desligados existem para o municipio (meses_informados < 12 = ano parcial
#    ou com competencias ausentes; saldo_ano = admitidos_ano - desligados_ano).
completo <- base[!is.na(base$saldo), , drop = FALSE]
grupo <- paste(completo$codigo_municipio, completo$ano)
somas <- rowsum(data.frame(admitidos_ano = completo$admitidos, desligados_ano = completo$desligados,
                           saldo_ano = completo$saldo, meses_informados = 1L), grupo)
anual <- data.frame(codigo_municipio = substr(rownames(somas), 1L, 7L),
                    ano = as.integer(substr(rownames(somas), 9L, 12L)),
                    somas, row.names = NULL, stringsAsFactors = FALSE)

# 4. Nome/UF oficiais e gravacao
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base, mensal = TRUE)
anual <- juntar_dicionario(anual, dicionario)
salvar_base_tratada(FONTE, anual, nome = "caged_anual_municipal")

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("admitidos", "desligados", "saldo",
               "admitidos_ano", "desligados_ano", "saldo_ano", "meses_informados"),
  descricao = c(
    "Empregados celetistas admitidos no mes (Novo Caged sem ajuste, serie ADMISNC do Ipeadata)",
    "Empregados celetistas desligados no mes (Novo Caged sem ajuste, serie DESLIGNC do Ipeadata)",
    "Saldo de movimentacao no mes: admitidos - desligados (vazio quando uma das series nao informa a competencia)",
    "Total de admitidos no ano, somando apenas os meses com admitidos e desligados informados",
    "Total de desligados no ano, somando apenas os meses com admitidos e desligados informados",
    "Saldo de movimentacao acumulado no ano: admitidos_ano - desligados_ano",
    "Numero de meses do ano com admitidos e desligados informados (menor que 12 = ano parcial ou com lacunas)"
  ),
  unidade = c(rep("pessoas", 3L), rep("pessoas", 3L), "meses"),
  periodicidade = c(rep("mensal", 3L), rep("anual", 4L)),
  tabela = c(rep("caged_municipal", 3L), rep("caged_anual_municipal", 4L)),
  fonte_url = "https://www.ipeadata.gov.br/",
  stringsAsFactors = FALSE
))
