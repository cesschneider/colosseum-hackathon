# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_ibge_censo_demografico.R
# FONTE: IBGE - Censos Demograficos 2000, 2010 e 2022 (tabelas SIDRA 1552 e 9514)
# OBJETIVO: Baixar e preservar, sem agregar, a populacao residente municipal
#           por grupos de idade e por sexo dos tres ultimos Censos.
# COBERTURA: Brasil, todos os municipios; anos censitarios 2000, 2010 e 2022.
# PERIODICIDADE: decenal
# ENDPOINT: https://apisidra.ibge.gov.br/values/t/1552/n6/in%20n3%20<UF>/v/93/p/<ano>/c1/0/c2/<sexo>/c286/0/c287/<idades>
#           https://apisidra.ibge.gov.br/values/t/9514/n6/in%20n3%20<UF>/v/93/p/2022/c2/<sexo>/c287/<idades>/c286/113635
# SAIDAS: dados/brutos/ibge_censo_demografico/sidra_<tabela>_<ano>_<idade|sexo>.rds
#         dados/brutos/ibge_censo_demografico/sidra_censo_assinatura.txt
# COMO EXECUTAR: Rscript fontes/ibge_censo_demografico/01_extracao_ibge_censo_demografico.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "ibge_censo_demografico"

VARIAVEL_SIDRA <- 93L   # Populacao residente (pessoas)
# Categorias de idade (classificacao c287): grupos quinquenais ate 75-79 anos e
# grupos finais, que diferem entre as tabelas:
#   1552 (2000/2010): 93099 = 80 a 89, 93100 = 90 a 99, 6653 = 100 ou mais
#   9514 (2022):      49108 = 80 a 84, 49109 = 85 a 89, 60040 = 90 a 94,
#                     60041 = 95 a 99, 6653 = 100 ou mais
IDADES_1552 <- c(93070L, 93084:93100, 6653L)
IDADES_9514 <- c(93070L, 93084:93098, 49108L, 49109L, 60040L, 60041L, 6653L)
# Plano de coleta: por ano, uma consulta por idade (sexo total) e uma por sexo
# (idade total). Os codigos de "total" e de sexo tambem diferem entre tabelas:
#   1552: c1/0 situacao do domicilio total, c2/0 sexo total (92956 homens,
#         92957 mulheres), c286/0 forma de declaracao total, c287/0 idade total
#   9514: c2/6794 sexo total (4 homens, 5 mulheres), c287/100362 idade total,
#         c286/113635 forma de declaracao total
PLANO <- data.frame(
  tabela = c(1552L, 1552L, 1552L, 1552L, 9514L, 9514L),
  ano = c(2000L, 2000L, 2010L, 2010L, 2022L, 2022L),
  tipo = rep(c("idade", "sexo"), 3L),
  classificacoes = c(
    paste0("/c1/0/c2/0/c286/0/c287/", paste(IDADES_1552, collapse = ",")),
    "/c1/0/c2/92956,92957/c286/0/c287/0",
    paste0("/c1/0/c2/0/c286/0/c287/", paste(IDADES_1552, collapse = ",")),
    "/c1/0/c2/92956,92957/c286/0/c287/0",
    paste0("/c2/6794/c287/", paste(IDADES_9514, collapse = ","), "/c286/113635"),
    "/c2/4,5/c287/100362/c286/113635"
  ),
  stringsAsFactors = FALSE
)
PLANO <- PLANO[PLANO$ano >= ano_inicial_efetivo(2000L), ]
if (!nrow(PLANO)) stop("Nenhum ano censitario dentro da janela temporal configurada.")
dir_saida <- dir_brutos(FONTE)
PLANO$destino <- file.path(dir_saida, sprintf("sidra_%d_%d_%s.rds", PLANO$tabela, PLANO$ano, PLANO$tipo))

salvar_rds <- function(objeto, destino) {
  temporario <- paste0(destino, ".part")
  saveRDS(objeto, temporario)
  if (file.exists(destino)) unlink(destino, force = TRUE)
  if (!file.rename(temporario, destino)) stop("Nao foi possivel gravar ", destino)
  invisible(destino)
}

# Reutilizacao: dados censitarios nao mudam, mas um bruto coletado com outro
# conjunto de UFs ativas (testes) precisa ser refeito. PAINEL_REBAIXAR=TRUE forca.
arquivo_assinatura <- file.path(dir_saida, "sidra_censo_assinatura.txt")
assinatura <- paste0("ufs=", paste(UFS_ATIVAS$uf, collapse = ","))
assinatura_gravada <- if (file.exists(arquivo_assinatura)) readLines(arquivo_assinatura, warn = FALSE)[1] else ""
reutilizar <- REUTILIZAR_BRUTOS && identical(assinatura_gravada, assinatura)

for (i in seq_len(nrow(PLANO))) {
  destino <- PLANO$destino[i]
  if (reutilizar && file.exists(destino)) {
    log_msg("Reutilizado: ", basename(destino))
    next
  }
  bruto <- sidra_consultar(PLANO$tabela[i], VARIAVEL_SIDRA, periodos = PLANO$ano[i],
                           classificacoes = PLANO$classificacoes[i])
  # Checagem minima: as colunas de valor e das classificacoes usadas no script 02.
  nomes <- remover_acentos(names(bruto))
  if (!all(c("Valor", "Sexo (Codigo)", "Idade (Codigo)") %in% nomes)) {
    stop("Retorno do SIDRA sem as colunas esperadas: ", paste(names(bruto), collapse = " | "))
  }
  salvar_rds(bruto, destino)
  log_msg("Bruto gravado: ", basename(destino), " (", nrow(bruto), " linhas)")
}
writeLines(assinatura, arquivo_assinatura)

registrar_execucao(FONTE, "extracao", paste0(nrow(PLANO), " consultas SIDRA em ", dir_saida))
