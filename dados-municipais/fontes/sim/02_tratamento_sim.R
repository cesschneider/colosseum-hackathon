# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_sim.R
# FONTE: Ministerio da Saude / DATASUS - SIM-DO (microdados de obitos)
# OBJETIVO: Agregar os microdados por municipio de residencia e ano: obitos,
#           idade media ao obito, homicidios (total e por sexo), suicidios,
#           obitos por causas externas e taxas por 100 mil habitantes.
# ENTRADAS: dados/brutos/sim/sim_do_<UF>_<ano>[_preliminar].rds
#           dados/brutos/sim/ipeadata_estima_po.csv (denominador das taxas)
#           dados/tratados/datasus_populacao/datasus_populacao_municipal.csv
#           (opcional: completa os anos sem estimativa municipal no Ipeadata)
# SAIDAS: dados/tratados/sim/sim_municipal.csv
#         dados/tratados/sim/sim_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/sim/02_tratamento_sim.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "sim"

dicionario <- carregar_dicionario_municipios()
dir_entrada <- dir_brutos(FONTE)
arquivos <- list.files(dir_entrada, pattern = "^sim_do_[A-Z]{2}_[0-9]{4}(_preliminar)?[.]rds$", full.names = TRUE)
if (!length(arquivos)) stop("Nenhum bruto encontrado. Execute o script 01 antes.")
brutos <- data.frame(
  arquivo = arquivos,
  uf = sub("^sim_do_([A-Z]{2})_.*$", "\\1", basename(arquivos)),
  ano = as.integer(sub("^sim_do_[A-Z]{2}_([0-9]{4}).*$", "\\1", basename(arquivos))),
  preliminar = grepl("_preliminar[.]rds$", arquivos),
  stringsAsFactors = FALSE
)
# Se um UF-ano tiver bruto definitivo e preliminar, o definitivo prevalece.
brutos <- brutos[order(brutos$uf, brutos$ano, brutos$preliminar), ]
brutos <- brutos[!duplicated(brutos[c("uf", "ano")]), ]
brutos <- brutos[brutos$uf %in% UFS_ATIVAS$uf & brutos$ano >= ano_inicial_efetivo(2000L), ]
if (!nrow(brutos)) stop("Nenhum bruto para as UFs/anos solicitados.")

# ---- Funcoes de decodificacao ---------------------------------------------------

idade_sim_para_anos <- function(x) {
  # IDADE do SIM tem 3 digitos: o primeiro e a unidade (0 minutos, 1 horas,
  # 2 dias, 3 meses, 4 anos, 5 = 100 anos + valor) e os dois ultimos o valor;
  # 9 = ignorado. Menores de um ano entram na media com idade zero.
  codigo <- gsub("[^0-9]", "", as.character(x))
  codigo <- ifelse(!is.na(codigo) & nzchar(codigo),
                   sprintf("%03d", suppressWarnings(as.integer(codigo))), NA_character_)
  unidade <- substr(codigo, 1L, 1L)
  valor <- suppressWarnings(as.integer(substr(codigo, 2L, 3L)))
  idade <- rep(NA_real_, length(codigo))
  idade[unidade %in% c("0", "1", "2", "3")] <- 0
  idade[unidade %in% "4"] <- valor[unidade %in% "4"]
  idade[unidade %in% "5"] <- 100 + valor[unidade %in% "5"]
  idade[!is.na(idade) & (idade < 0 | idade > 130)] <- NA_real_
  idade
}

posicao_cid <- function(x) {
  # Posicao ordinal de um codigo CID-10 pela letra e pelos dois primeiros
  # digitos (X85 -> 2485), para testar intervalos como X85-Y09.
  x <- toupper(gsub("[^A-Za-z0-9]", "", as.character(x)))
  letra <- match(substr(x, 1L, 1L), LETTERS)
  letra * 100L + suppressWarnings(as.integer(substr(x, 2L, 3L)))
}

cid_entre <- function(posicao, inicio, fim) {
  !is.na(posicao) & posicao >= posicao_cid(inicio) & posicao <= posicao_cid(fim)
}

agregar_arquivo <- function(arquivo, ano) {
  # Uma linha por obito -> somas por codigo de residencia (6 digitos do SIM).
  d <- readRDS(arquivo)
  if (!nrow(d)) return(NULL)
  codigo6 <- substr(gsub("[^0-9]", "", as.character(d$CODMUNRES)), 1L, 6L)
  idade <- idade_sim_para_anos(d$IDADE)
  sexo <- trimws(as.character(d$SEXO))          # 1 = masculino, 2 = feminino
  posicao <- posicao_cid(d$CAUSABAS)
  homicidio <- cid_entre(posicao, "X85", "Y09")  # agressoes
  medidas <- cbind(
    obitos = rep(1, nrow(d)),
    obitos_com_idade = !is.na(idade),
    soma_idade = ifelse(is.na(idade), 0, idade),
    homicidios = homicidio,
    homicidios_masculinos = homicidio & sexo %in% "1",
    homicidios_femininos = homicidio & sexo %in% "2",
    suicidios = cid_entre(posicao, "X60", "X84"),              # lesoes autoprovocadas
    obitos_causas_externas = cid_entre(posicao, "V01", "Y98")  # capitulo XX da CID-10
  )
  valido <- grepl("^[0-9]{6}$", codigo6)
  somas <- rowsum(medidas[valido, , drop = FALSE], codigo6[valido])
  data.frame(codigo6 = rownames(somas), ano = as.integer(ano), somas, row.names = NULL, stringsAsFactors = FALSE)
}

# ---- 1. Agregacao por arquivo e soma por municipio-ano ---------------------------
# Os arquivos sao organizados pela UF de ocorrencia; somando todas as UFs por
# CODMUNRES obtem-se o total por municipio de residencia.
log_msg("Agregando ", nrow(brutos), " arquivos UF-ano (", min(brutos$ano), "-", max(brutos$ano), ")")
parciais <- do.call(rbind, Map(agregar_arquivo, brutos$arquivo, brutos$ano))
MEDIDAS <- setdiff(names(parciais), c("codigo6", "ano"))
somas <- rowsum(as.matrix(parciais[MEDIDAS]), paste(parciais$codigo6, parciais$ano))
totais <- data.frame(
  codigo6 = sub(" .*$", "", rownames(somas)),
  ano = as.integer(sub("^.* ", "", rownames(somas))),
  somas, row.names = NULL, stringsAsFactors = FALSE
)
totais$codigo_municipio <- codigo6_para_7(totais$codigo6, dicionario)
descartados <- is.na(totais$codigo_municipio)
if (any(descartados)) {
  log_msg("Aviso: ", sum(totais$obitos[descartados]), " obitos (",
          round(100 * sum(totais$obitos[descartados]) / sum(totais$obitos), 2),
          "%) com residencia fora do dicionario (ignorado, exterior ou UF inativa) foram descartados.")
}
totais <- totais[!descartados, ]

# ---- 2. Painel municipio-ano ------------------------------------------------------
# Municipio sem obito registrado recebe zero apenas nos anos em que o arquivo
# da sua UF existe; sem o arquivo, a contagem fica NA (dado nao coletado).
anos <- sort(unique(brutos$ano))
base <- merge(expand.grid(codigo_municipio = dicionario$codigo_municipio, ano = anos, stringsAsFactors = FALSE),
              totais[c("codigo_municipio", "ano", MEDIDAS)], by = c("codigo_municipio", "ano"), all.x = TRUE)
uf_base <- dicionario$uf[match(base$codigo_municipio, dicionario$codigo_municipio)]
coberto <- paste(uf_base, base$ano) %in% paste(brutos$uf, brutos$ano)
for (v in MEDIDAS) base[[v]][is.na(base[[v]]) & coberto] <- 0
base$idade_media_obito <- ifelse(base$obitos_com_idade > 0, base$soma_idade / base$obitos_com_idade, NA_real_)
base$dados_preliminares <- as.integer(base$ano %in% brutos$ano[brutos$preliminar])

# ---- 3. Taxas por 100 mil habitantes ----------------------------------------------
# Denominador: ESTIMA_PO (Ipeadata). Anos sem estimativa municipal no Ipeadata
# (anos de censo/contagem: 2007, 2010, 2022, 2023) sao completados com a
# populacao total da fonte datasus_populacao, quando ja tratada.
arquivo_pop <- file.path(dir_entrada, "ipeadata_estima_po.csv")
chave_base <- paste(base$codigo_municipio, base$ano)
base$populacao <- NA_real_
if (file.exists(arquivo_pop)) {
  populacao <- as.data.frame(ler_csv(arquivo_pop))
  base$populacao <- populacao$valor[match(chave_base, paste(padronizar_codigo7(populacao$codigo_municipio), populacao$ano))]
} else {
  log_msg("Aviso: ", basename(arquivo_pop), " ausente (execute o script 01); taxas ficarao NA.")
}
arquivo_datasus <- file.path(DIR_TRATADOS, "datasus_populacao", "datasus_populacao_municipal.csv")
if (file.exists(arquivo_datasus)) {
  complemento <- as.data.frame(ler_csv(arquivo_datasus))
  faltante <- is.na(base$populacao)
  base$populacao[faltante] <- complemento$populacao_total[
    match(chave_base[faltante], paste(padronizar_codigo7(complemento$codigo_municipio), complemento$ano))]
  log_msg("Populacao complementada com datasus_populacao em ", sum(faltante & !is.na(base$populacao)), " municipio-ano.")
}
taxa <- function(x) ifelse(!is.na(base$populacao) & base$populacao > 0, 1e5 * x / base$populacao, NA_real_)
base$taxa_mortalidade_100mil <- taxa(base$obitos)
base$taxa_homicidios_100mil <- taxa(base$homicidios)
base$taxa_suicidios_100mil <- taxa(base$suicidios)
base$taxa_causas_externas_100mil <- taxa(base$obitos_causas_externas)

# ---- 4. Nome/UF oficiais e gravacao -----------------------------------------------
base <- base[c("codigo_municipio", "ano", "obitos", "idade_media_obito", "homicidios",
               "homicidios_masculinos", "homicidios_femininos", "suicidios", "obitos_causas_externas",
               "taxa_mortalidade_100mil", "taxa_homicidios_100mil", "taxa_suicidios_100mil",
               "taxa_causas_externas_100mil", "dados_preliminares")]
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("obitos", "idade_media_obito", "homicidios", "homicidios_masculinos", "homicidios_femininos",
               "suicidios", "obitos_causas_externas", "taxa_mortalidade_100mil", "taxa_homicidios_100mil",
               "taxa_suicidios_100mil", "taxa_causas_externas_100mil", "dados_preliminares"),
  descricao = c(
    "Obitos de residentes no municipio (declaracoes de obito do SIM-DO, por ano de ocorrencia)",
    "Idade media ao obito, em anos completos (menores de um ano contam como zero; idade ignorada excluida)",
    "Homicidios: obitos por agressao, causa basica CID-10 X85 a Y09",
    "Homicidios de pessoas do sexo masculino (SEXO = 1)",
    "Homicidios de pessoas do sexo feminino (SEXO = 2)",
    "Suicidios: obitos por lesoes autoprovocadas, causa basica CID-10 X60 a X84",
    "Obitos por causas externas, causa basica CID-10 V01 a Y98 (capitulo XX)",
    "Obitos por 100 mil habitantes (denominador: ESTIMA_PO do Ipeadata, complementado por datasus_populacao)",
    "Homicidios por 100 mil habitantes",
    "Suicidios por 100 mil habitantes",
    "Obitos por causas externas por 100 mil habitantes",
    "1 quando o ano vem de arquivo preliminar do DATASUS (sujeito a revisao; ano corrente e parcial), 0 quando definitivo"
  ),
  unidade = c("obitos", "anos", rep("obitos", 5L), rep("por 100 mil habitantes", 4L), "indicador 0/1"),
  periodicidade = "anual",
  tabela = "SIM-DO (DO<UF><ANO>.dbc), campos CODMUNRES, IDADE, SEXO, CAUSABAS",
  fonte_url = "ftp://ftp.datasus.gov.br/dissemin/publicos/SIM/CID10/DORES/",
  stringsAsFactors = FALSE
))
