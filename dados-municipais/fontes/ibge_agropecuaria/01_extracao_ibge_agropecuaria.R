# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_ibge_agropecuaria.R
# FONTE: IBGE/SIDRA - Producao Agricola Municipal (PAM, tabelas 1612 e 1613) e
#        Pesquisa da Pecuaria Municipal (PPM, aquicultura, tabela 3940);
#        BCB/SGS - IPCA (serie 433) para o deflator usado no tratamento
# OBJETIVO: Baixar e preservar, sem transformar, o retorno da API SIDRA para o
#           valor da producao e a area colhida das lavouras temporarias e
#           permanentes (categoria total) e para o valor e a producao em kg da
#           aquicultura (21 produtos medidos em quilogramas).
# COBERTURA: Brasil, todos os municipios; PAM 1974 ate o mais recente,
#            PPM/aquicultura 2013 ate o mais recente
# PERIODICIDADE: anual
# ENDPOINT: https://apisidra.ibge.gov.br/values (tabelas 1612, 1613 e 3940)
#           https://servicodados.ibge.gov.br/api/v3/agregados/<tabela>/periodos
#           https://api.bcb.gov.br/dados/serie/bcdata.sgs.433 (IPCA mensal)
# SAIDAS: dados/brutos/ibge_agropecuaria/sidra_<tabela>_<conteudo>.rds
#         dados/brutos/ibge_agropecuaria/deflator_ipca_anual.csv
# COMO EXECUTAR: Rscript fontes/ibge_agropecuaria/01_extracao_ibge_agropecuaria.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "ibge_agropecuaria"

ANO_INICIAL <- ano_inicial_efetivo(1974L)   # inicio da serie da PAM no SIDRA
ANO_BASE_PRECOS <- 2024L                    # ano-base das colunas deflacionadas (script 02)
dir_saida <- dir_brutos(FONTE)

# A API SIDRA recusa requisicoes com mais de 50.000 valores (municipios x
# variaveis x periodos x categorias). Como a biblioteca consulta uma UF por
# vez, os periodos sao fatiados em blocos dimensionados pela maior UF ativa.
LIMITE_VALORES_SIDRA <- 50000L
MAX_MUNICIPIOS_UF <- max(table(carregar_dicionario_municipios()$uf))

# Produtos da aquicultura (tabela 3940, classificacao 654) medidos em quilogramas.
# Alevinos (32886), larvas e pos-larvas de camarao (32888) e sementes de
# moluscos (32890) sao medidos em milheiros e por isso ficam fora da soma em kg.
PRODUTOS_AQUICULTURA_KG <- c(32861L, 32865L, 32866L, 32867L, 32868L, 32869L, 32870L,
                             32871L, 32872L, 32873L, 32874L, 32875L, 32876L, 32877L,
                             32878L, 32879L, 32880L, 32881L, 32887L, 32889L, 32891L)

# 1. Plano de coleta: um arquivo por consulta, todas as UFs ativas e todos os
#    municipios. Variaveis: 215 = valor da producao, 216 = area colhida,
#    4146 = producao da aquicultura. Categoria 0 = total da classificacao.
plano <- data.frame(
  arquivo = c("sidra_1612_lavouras_temporarias", "sidra_1613_lavouras_permanentes",
              "sidra_3940_aquicultura_valor", "sidra_3940_aquicultura_producao_kg"),
  tabela = c(1612L, 1613L, 3940L, 3940L),
  variaveis = c("215,216", "215,216", "215", "4146"),
  classificacoes = c("/c81/0", "/c82/0", "/c654/0",
                     paste0("/c654/", paste(PRODUTOS_AQUICULTURA_KG, collapse = ","))),
  categorias = c(1L, 1L, 1L, length(PRODUTOS_AQUICULTURA_KG)),
  ano_inicial_tabela = c(1974L, 1974L, 2013L, 2013L),
  stringsAsFactors = FALSE
)

anos_disponiveis <- function(tabela, ano_inicial_tabela) {
  # Periodos publicados segundo a API de agregados; se ela falhar, assume a
  # serie ate o ano corrente (a API de valores ignora anos inexistentes).
  anos <- tryCatch(as.integer(obter_json_url(paste0(URL_IBGE_AGREGADOS, "/", tabela, "/periodos"))$id),
                   error = function(e) integer())
  if (!length(anos)) {
    log_msg("Aviso: periodos da tabela ", tabela, " indisponiveis; assumindo ", ano_inicial_tabela, "-", ANO_ATUAL)
    anos <- seq(ano_inicial_tabela, ANO_ATUAL)
  }
  anos <- sort(anos[anos >= ANO_INICIAL])
  if (!length(anos)) stop("Tabela ", tabela, " sem periodos a partir de ", ANO_INICIAL, ".")
  anos
}

coluna_sidra <- function(dados, nome_ascii) {
  achada <- names(dados)[remover_acentos(names(dados)) == nome_ascii]
  if (!length(achada)) stop("Coluna nao encontrada na resposta do SIDRA: ", nome_ascii)
  dados[[achada[[1L]]]]
}

validar_resposta <- function(dados, variaveis) {
  # A biblioteca ignora silenciosamente uma UF cuja resposta nao seja tabular;
  # aqui se exige toda UF ativa em todo ano devolvido e todas as variaveis.
  ufs <- uf_por_codigo(coluna_sidra(dados, "Municipio (Codigo)"))
  anos <- as.integer(coluna_sidra(dados, "Ano (Codigo)"))
  esperado <- expand.grid(uf = UFS_ATIVAS$uf, ano = sort(unique(anos)), stringsAsFactors = FALSE)
  chave_esperada <- paste(esperado$uf, esperado$ano)
  faltam <- chave_esperada[!chave_esperada %in% unique(paste(ufs, anos))]
  if (length(faltam)) stop("Resposta do SIDRA incompleta (UF-ano ausentes): ", paste(head(faltam, 10L), collapse = ", "))
  vars_faltantes <- setdiff(variaveis, unique(coluna_sidra(dados, "Variavel (Codigo)")))
  if (length(vars_faltantes)) stop("Resposta do SIDRA sem a(s) variavel(is): ", paste(vars_faltantes, collapse = ", "))
  invisible(anos)
}

# 2. Download com reutilizacao. Cada arquivo cobre a serie inteira; uma nova
#    divulgacao anual da PAM/PPM so entra com PAINEL_REBAIXAR=TRUE (ver README).
for (i in seq_len(nrow(plano))) {
  destino <- file.path(dir_saida, paste0(plano$arquivo[i], ".rds"))
  if (REUTILIZAR_BRUTOS && file.exists(destino)) {
    log_msg("Reutilizado: ", basename(destino))
    next
  }
  variaveis <- strsplit(plano$variaveis[i], ",")[[1L]]
  anos <- anos_disponiveis(plano$tabela[i], plano$ano_inicial_tabela[i])
  anos_por_bloco <- max(1L, LIMITE_VALORES_SIDRA %/% (MAX_MUNICIPIOS_UF * length(variaveis) * plano$categorias[i]))
  blocos <- split(anos, ceiling(seq_along(anos) / anos_por_bloco))
  log_msg(plano$arquivo[i], ": ", min(anos), "-", max(anos), " em ", length(blocos), " bloco(s) de ate ",
          anos_por_bloco, " ano(s)")
  dados <- do.call(rbind, lapply(blocos, function(bloco) {
    sidra_consultar(plano$tabela[i], variaveis, periodos = paste0(min(bloco), "-", max(bloco)),
                    classificacoes = plano$classificacoes[i])
  }))
  rownames(dados) <- NULL
  anos_obtidos <- validar_resposta(dados, variaveis)
  saveRDS(dados, destino)
  log_msg("Gravado: ", basename(destino), " (", nrow(dados), " linhas, ", min(anos_obtidos), "-", max(anos_obtidos), ")")
}

# 3. Deflator IPCA (media anual do indice, base ANO_BASE_PRECOS). Sempre
#    rebaixado, pois e pequeno e o ano corrente ainda acumula meses; se o BCB
#    estiver fora do ar, um arquivo anterior e reaproveitado.
destino_deflator <- file.path(dir_saida, "deflator_ipca_anual.csv")
deflator <- tryCatch(deflator_ipca_anual(ANO_BASE_PRECOS), error = function(e) e)
if (inherits(deflator, "error")) {
  if (!file.exists(destino_deflator)) stop("Falha ao obter o IPCA do BCB: ", conditionMessage(deflator))
  log_msg("Aviso: IPCA indisponivel (", conditionMessage(deflator), "); reutilizado ", basename(destino_deflator))
} else {
  escrever_csv(deflator, destino_deflator)
  log_msg("Gravado: ", basename(destino_deflator), " (base ", ANO_BASE_PRECOS, ", ",
          min(deflator$ano), "-", max(deflator$ano), ")")
}

registrar_execucao(FONTE, "extracao", paste0(nrow(plano), " consultas SIDRA + deflator IPCA em ", dir_saida))
