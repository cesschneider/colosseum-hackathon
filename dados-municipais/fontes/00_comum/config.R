# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# ARQUIVO: config.R
# PAPEL:   Configuracao central de todas as fontes do painel de dados municipais.
#          Nenhum script de fonte deve conter caminho absoluto, nome de cliente,
#          recorte territorial fixo ou lista de municipios embutida: tudo vem daqui.
# CARREGAMENTO: nao execute diretamente; e lido por funcoes_comuns.R, que define
#          .DIR_COMUM (pasta fontes/00_comum) antes de fazer o source().
# ------------------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# Nome do projeto (aparece em metadados e no User-Agent das requisicoes).
PROJETO_NOME <- Sys.getenv("PAINEL_PROJETO", unset = "painel-dados-municipais-br")

# Raiz do repositorio: a pasta que contem "fontes/". Pode ser sobrescrita por
# variavel de ambiente para rodar em servidor/CI.
.localizar_raiz <- function() {
  configurada <- Sys.getenv("PAINEL_RAIZ", unset = "")
  if (nzchar(configurada)) return(normalizePath(configurada, winslash = "/", mustWork = TRUE))
  if (exists(".DIR_COMUM", inherits = TRUE)) {
    return(normalizePath(dirname(dirname(get(".DIR_COMUM"))), winslash = "/", mustWork = TRUE))
  }
  candidatos <- c(getwd(), dirname(getwd()), dirname(dirname(getwd())))
  for (cand in candidatos) {
    if (dir.exists(file.path(cand, "fontes", "00_comum"))) {
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
    }
  }
  stop("Nao foi possivel localizar a raiz do projeto. Defina PAINEL_RAIZ.")
}

DIR_RAIZ    <- .localizar_raiz()
DIR_FONTES  <- file.path(DIR_RAIZ, "fontes")
DIR_DADOS   <- Sys.getenv("PAINEL_DADOS", unset = file.path(DIR_RAIZ, "dados"))

# Subpastas padrao. Cada fonte grava em dados/brutos/<fonte> e dados/tratados/<fonte>.
DIR_AUXILIARES <- file.path(DIR_DADOS, "auxiliares")
DIR_BRUTOS     <- file.path(DIR_DADOS, "brutos")
DIR_TRATADOS   <- file.path(DIR_DADOS, "tratados")
DIR_PAINEL     <- file.path(DIR_DADOS, "painel")
DIR_LOGS       <- file.path(DIR_DADOS, "logs")

# Cobertura territorial: TODO O BRASIL. As 27 UFs com codigo IBGE (2 digitos).
UFS <- data.frame(
  cod_uf = c(11L, 12L, 13L, 14L, 15L, 16L, 17L, 21L, 22L, 23L, 24L, 25L, 26L, 27L,
             28L, 29L, 31L, 32L, 33L, 35L, 41L, 42L, 43L, 50L, 51L, 52L, 53L),
  uf = c("RO", "AC", "AM", "RR", "PA", "AP", "TO", "MA", "PI", "CE", "RN", "PB",
         "PE", "AL", "SE", "BA", "MG", "ES", "RJ", "SP", "PR", "SC", "RS", "MS",
         "MT", "GO", "DF"),
  nome_uf = c("Rondonia", "Acre", "Amazonas", "Roraima", "Para", "Amapa",
              "Tocantins", "Maranhao", "Piaui", "Ceara", "Rio Grande do Norte",
              "Paraiba", "Pernambuco", "Alagoas", "Sergipe", "Bahia",
              "Minas Gerais", "Espirito Santo", "Rio de Janeiro", "Sao Paulo",
              "Parana", "Santa Catarina", "Rio Grande do Sul",
              "Mato Grosso do Sul", "Mato Grosso", "Goias", "Distrito Federal"),
  regiao = c(rep("Norte", 7), rep("Nordeste", 9), rep("Sudeste", 4),
             rep("Sul", 3), rep("Centro-Oeste", 4)),
  stringsAsFactors = FALSE
)

# Filtro opcional de UFs para testes rapidos (ex.: PAINEL_UFS="MG,ES").
# Vazio = todas as 27 UFs (padrao do projeto).
UFS_ATIVAS <- local({
  filtro <- trimws(strsplit(Sys.getenv("PAINEL_UFS", unset = ""), ",")[[1]])
  filtro <- toupper(filtro[nzchar(filtro)])
  if (length(filtro)) UFS[UFS$uf %in% filtro, , drop = FALSE] else UFS
})

# Janela temporal opcional para testes (ex.: PAINEL_ANO_INICIAL=2020).
# Vazio = serie historica completa de cada fonte.
ANO_INICIAL_GLOBAL <- local({
  v <- Sys.getenv("PAINEL_ANO_INICIAL", unset = "")
  if (nzchar(v)) as.integer(v) else NA_integer_
})

# Formato dos CSVs tratados: padrao internacional (virgula e ponto decimal),
# pensado para consumo por aplicacoes web (JS/Python/DuckDB). Os brutos sao
# preservados como vieram da fonte.
CSV_SEP <- ","
CSV_DEC <- "."
CSV_ENCODING <- "UTF-8"

# Rede
USER_AGENT        <- paste0("Mozilla/5.0 (compatible; ", PROJETO_NOME, "/1.0; coleta de dados publicos)")
TIMEOUT_PADRAO    <- as.integer(Sys.getenv("PAINEL_TIMEOUT", unset = "1800"))
TENTATIVAS_PADRAO <- 3L
REUTILIZAR_BRUTOS <- !identical(toupper(Sys.getenv("PAINEL_REBAIXAR", unset = "FALSE")), "TRUE")

# Ano corrente (limite superior padrao das coletas).
ANO_ATUAL <- as.integer(format(Sys.Date(), "%Y"))

# Endpoints compartilhados por varias fontes
URL_IBGE_LOCALIDADES <- "https://servicodados.ibge.gov.br/api/v1/localidades/municipios?view=nivelado"
URL_IBGE_AGREGADOS   <- "https://servicodados.ibge.gov.br/api/v3/agregados"
URL_SIDRA_VALUES     <- "https://apisidra.ibge.gov.br/values"
URL_IPEADATA_ODATA   <- "https://www.ipeadata.gov.br/api/odata4"
URL_BCB_SGS          <- "https://api.bcb.gov.br/dados/serie/bcdata.sgs."

# Colunas-chave obrigatorias em toda base tratada municipal.
CHAVES_MUNICIPAIS <- c("codigo_municipio", "nome_municipio", "uf", "ano")
