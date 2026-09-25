# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_ibge_pib_municipal.R
# FONTE: IBGE - Produto Interno Bruto dos Municipios (tabela SIDRA 5938)
# OBJETIVO: Baixar e preservar, sem transformar, o PIB, os impostos liquidos e
#           os componentes do valor adicionado bruto de todos os municipios do
#           Brasil, alem das series municipais de populacao do Ipeadata usadas
#           no calculo do PIB per capita (script 02).
# COBERTURA: Brasil, todos os municipios; 2002 ate o ultimo ano publicado.
# PERIODICIDADE: anual
# ENDPOINT: https://apisidra.ibge.gov.br/values/t/5938/n6/in%20n3%20<UF>/v/37,498,513,517,525,543,6575/p/<anos>
#           https://servicodados.ibge.gov.br/api/v3/agregados/5938/periodos
#           https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='ESTIMA_PO')
#           https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='POPTOT')
# SAIDAS: dados/brutos/ibge_pib_municipal/sidra_5938_pib_municipal.rds
#         dados/brutos/ibge_pib_municipal/sidra_5938_assinatura.txt
#         dados/brutos/ibge_pib_municipal/ipeadata_ESTIMA_PO.csv
#         dados/brutos/ibge_pib_municipal/ipeadata_POPTOT.csv
# COMO EXECUTAR: Rscript fontes/ibge_pib_municipal/01_extracao_ibge_pib_municipal.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "ibge_pib_municipal"

TABELA_SIDRA <- 5938L
# 37 PIB | 498 VAB total | 513 VAB agropecuaria | 517 VAB industria |
# 525 VAB administracao publica | 543 impostos liquidos de subsidios |
# 6575 VAB servicos, exclusive administracao publica (todos em mil reais correntes)
VARIAVEIS_SIDRA <- c(37L, 498L, 513L, 517L, 525L, 543L, 6575L)
# A API SIDRA recusa (HTTP 400) consultas com mais de ~50 mil valores. Os anos
# sao divididos em blocos dimensionados pela UF com mais municipios.
LIMITE_VALORES_CONSULTA <- 49000L
# Populacao para o per capita: ESTIMA_PO (estimativas anuais de 1 de julho) e
# POPTOT (censos e contagens: 2000, 2007, 2010, 2022, anos sem estimativa).
SERIES_IPEADATA <- c("ESTIMA_PO", "POPTOT")
ANO_INICIAL <- ano_inicial_efetivo(2002L)
dir_saida <- dir_brutos(FONTE)

salvar_rds <- function(objeto, destino) {
  temporario <- paste0(destino, ".part")
  saveRDS(objeto, temporario)
  if (file.exists(destino)) unlink(destino, force = TRUE)
  if (!file.rename(temporario, destino)) stop("Nao foi possivel gravar ", destino)
  invisible(destino)
}

# 1. Descoberta dos anos publicados (API de agregados do IBGE)
periodos <- obter_json_url(paste0(URL_IBGE_AGREGADOS, "/", TABELA_SIDRA, "/periodos"))
anos <- sort(as.integer(periodos$id))
anos <- anos[!is.na(anos) & anos >= ANO_INICIAL]
if (!length(anos)) stop("Nenhum periodo da tabela ", TABELA_SIDRA, " a partir de ", ANO_INICIAL, ".")
log_msg("Tabela ", TABELA_SIDRA, ": anos publicados ", min(anos), "-", max(anos))

# 2. Reutilizacao: o bruto so e reaproveitado se as UFs ativas e os anos
#    publicados forem os mesmos da coleta anterior (o IBGE acrescenta um ano e
#    revisa os anteriores a cada divulgacao). PAINEL_REBAIXAR=TRUE forca a coleta.
arquivo_bruto <- file.path(dir_saida, "sidra_5938_pib_municipal.rds")
arquivo_assinatura <- file.path(dir_saida, "sidra_5938_assinatura.txt")
assinatura <- paste0("ufs=", paste(UFS_ATIVAS$uf, collapse = ","), ";anos=", paste(anos, collapse = ","))
assinatura_gravada <- if (file.exists(arquivo_assinatura)) readLines(arquivo_assinatura, warn = FALSE)[1] else ""
reutilizar <- REUTILIZAR_BRUTOS && file.exists(arquivo_bruto) && identical(assinatura_gravada, assinatura)

if (reutilizar) {
  log_msg("Reutilizado: ", basename(arquivo_bruto), " (mesmas UFs e anos publicados)")
} else {
  # 3. Blocos de anos: municipios da maior UF x variaveis x anos <= limite
  municipios_por_uf <- table(carregar_dicionario_municipios()$uf)
  anos_por_bloco <- max(1L, floor(LIMITE_VALORES_CONSULTA / (max(municipios_por_uf) * length(VARIAVEIS_SIDRA))))
  blocos <- split(anos, ceiling(seq_along(anos) / anos_por_bloco))
  log_msg(length(blocos), " bloco(s) de ate ", anos_por_bloco, " anos, ", nrow(UFS_ATIVAS), " UF(s) por bloco")
  bruto <- do.call(rbind, lapply(blocos, function(bloco) {
    sidra_consultar(TABELA_SIDRA, VARIAVEIS_SIDRA, periodos = bloco)
  }))
  rownames(bruto) <- NULL
  # Checagem minima: as sete variaveis precisam estar no retorno.
  col_variavel <- names(bruto)[remover_acentos(names(bruto)) == "Variavel (Codigo)"]
  if (!length(col_variavel) || !"Valor" %in% names(bruto)) stop("Retorno do SIDRA sem as colunas esperadas.")
  faltantes <- setdiff(VARIAVEIS_SIDRA, as.integer(unique(bruto[[col_variavel]])))
  if (length(faltantes)) stop("Variaveis ausentes no retorno do SIDRA: ", paste(faltantes, collapse = ", "))
  salvar_rds(bruto, arquivo_bruto)
  writeLines(assinatura, arquivo_assinatura)
  log_msg("Bruto gravado: ", basename(arquivo_bruto), " (", nrow(bruto), " linhas)")
}

# 4. Populacao municipal do Ipeadata (renovada junto com o PIB)
for (serie in SERIES_IPEADATA) {
  destino <- file.path(dir_saida, paste0("ipeadata_", serie, ".csv"))
  if (reutilizar && file.exists(destino)) {
    log_msg("Reutilizado: ", basename(destino))
    next
  }
  populacao <- ipeadata_municipal(serie)
  populacao <- populacao[!is.na(populacao$codigo_municipio) & !is.na(populacao$valor), ]
  if (!nrow(populacao)) stop("Serie ", serie, " do Ipeadata sem valores municipais.")
  escrever_csv(populacao, destino)
  log_msg("Gravado: ", basename(destino), " (", nrow(populacao), " linhas, ",
          min(populacao$ano), "-", max(populacao$ano), ")")
}

registrar_execucao(FONTE, "extracao", paste0("SIDRA 5938 ", min(anos), "-", max(anos),
                                             " + Ipeadata ", paste(SERIES_IPEADATA, collapse = "/")))
