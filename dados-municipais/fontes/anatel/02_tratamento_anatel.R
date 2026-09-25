# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_anatel.R
# FONTE: Anatel - Acessos de Banda Larga Fixa + Ipeadata/IBGE - populacao
# OBJETIVO: Ler os brutos, somar os acessos de todas as prestadoras/tecnologias
#           por municipio-mes e gravar a base municipal anual: acessos em
#           dezembro, media mensal do ano, abertura por meio de acesso,
#           populacao e densidade por 100 habitantes.
# ENTRADAS: dados/brutos/anatel/acessos_banda_larga_fixa.zip
#           dados/brutos/anatel/ipeadata_ESTIMA_PO.csv, ipeadata_POPTOT.csv
# SAIDAS: dados/tratados/anatel/anatel_municipal.csv
#         dados/tratados/anatel/anatel_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/anatel/02_tratamento_anatel.R
#   Para testes: PAINEL_ANO_INICIAL=2023 (le apenas os arquivos desses anos)
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table"))
library(data.table)
FONTE <- "anatel"

ANO_INICIAL <- ano_inicial_efetivo(2007L)
dicionario <- carregar_dicionario_municipios()
dir_entrada <- dir_brutos(FONTE)
zip_anatel <- file.path(dir_entrada, "acessos_banda_larga_fixa.zip")
if (!file.exists(zip_anatel)) stop("Zip da Anatel ausente. Execute o script 01 antes.")

# 1. Arquivos a ler. O zip traz, por faixa de anos, o CSV longo
#    (Ano;Mes;...;Acessos, ~7,6 GB no total) e o CSV "_Colunas", com os
#    mesmos registros em formato largo (um mes por coluna, ~1 GB no total).
#    Os dois sao identicos (totais por mes e por municipio conferidos);
#    usa-se o largo por ser muito mais leve. Formato: separador ";", UTF-8,
#    codigo IBGE de 7 digitos, celula vazia = nenhum acesso no mes.
membros <- listar_membros_zip(zip_anatel)
membros <- membros[grepl("^Acessos_Banda_Larga_Fixa_[0-9_-]+_Colunas[.]csv$", membros, ignore.case = TRUE)]
if (!length(membros)) stop("Nenhum CSV '_Colunas' encontrado no zip da Anatel.")
ano_final_membro <- vapply(membros, function(m) {
  max(as.integer(regmatches(m, gregexpr("(19|20)[0-9]{2}", m))[[1L]]))
}, integer(1L))
membros <- membros[ano_final_membro >= ANO_INICIAL]
log_msg(length(membros), " arquivo(s) a processar a partir de ", ANO_INICIAL, ".")

ler_membro <- function(membro) {
  log_msg("Lendo ", membro, "...")
  pasta_tmp <- tempfile("anatel_")
  on.exit(unlink(pasta_tmp, recursive = TRUE, force = TRUE), add = TRUE)
  descompactar_zip(zip_anatel, pasta_tmp, membros = membro)
  csv <- file.path(pasta_tmp, membro)
  cabecalho <- names(fread(csv, sep = ";", nrows = 0L, encoding = "UTF-8", check.names = FALSE))
  col_codigo <- cabecalho[normalizar_nome(cabecalho) == "codigo ibge municipio"]
  col_meio <- cabecalho[normalizar_nome(cabecalho) == "meio de acesso"]
  col_meses <- cabecalho[grepl("^[0-9]{4}-[0-9]{2}$", cabecalho)]
  if (length(col_codigo) != 1L || length(col_meio) != 1L || !length(col_meses)) {
    stop("Layout inesperado em ", membro, ": ", paste(cabecalho, collapse = " | "))
  }
  x <- fread(csv, sep = ";", select = c(col_codigo, col_meio, col_meses), encoding = "UTF-8",
             check.names = FALSE, showProgress = FALSE,
             colClasses = list(character = c(col_codigo, col_meio), numeric = col_meses))
  setnames(x, c(col_codigo, col_meio), c("codigo_municipio", "meio"))
  x[, codigo_municipio := padronizar_codigo7(codigo_municipio)]
  x <- x[!is.na(codigo_municipio)]
  x <- melt(x, id.vars = c("codigo_municipio", "meio"), variable.name = "periodo",
            value.name = "acessos", variable.factor = FALSE)
  x <- x[!is.na(acessos)]
  x[, `:=`(ano = as.integer(substr(periodo, 1L, 4L)), mes = as.integer(substr(periodo, 6L, 7L)))]
  x <- x[ano >= ANO_INICIAL & mes %in% 1:12]
  # Devolve apenas os agregados necessarios (total por municipio-mes e
  # dezembro por meio de acesso) para nao acumular milhoes de linhas.
  list(total = x[, .(acessos = sum(acessos)), by = .(codigo_municipio, ano, mes)],
       dezembro = x[mes == 12L, .(acessos = sum(acessos)), by = .(codigo_municipio, ano, meio)])
}

lidos <- lapply(membros, ler_membro)
total_mensal <- rbindlist(lapply(lidos, `[[`, "total"), use.names = TRUE)
dezembro <- rbindlist(lapply(lidos, `[[`, "dezembro"), use.names = TRUE)
rm(lidos)
if (!nrow(total_mensal)) stop("Nenhum registro a partir de ", ANO_INICIAL, " nos arquivos da Anatel.")

# 2. Anos fechados: somente anos em que dezembro ja foi publicado (o ano
#    corrente fica de fora). Em 2007-2010 a Anatel publicou apenas marco,
#    junho, setembro e dezembro: a media mensal usa os meses informados.
meses_ano <- total_mensal[, .(meses_informados = uniqueN(mes), tem_dezembro = 12L %in% mes), by = ano]
anos_abertos <- meses_ano[tem_dezembro == FALSE, ano]
if (length(anos_abertos)) log_msg("Ano(s) sem dezembro publicado, ignorado(s): ", paste(anos_abertos, collapse = ", "))
total_mensal <- merge(total_mensal[ano %in% meses_ano[tem_dezembro == TRUE, ano]],
                      meses_ano[, .(ano, meses_informados)], by = "ano")
if (!nrow(total_mensal)) stop("Nenhum ano fechado (com dezembro) encontrado na base da Anatel.")

anual <- total_mensal[, .(
  acessos_banda_larga_fixa = sum(acessos[mes == 12L]),
  acessos_media_mensal = sum(acessos) / meses_informados[1L],
  meses_informados = meses_informados[1L]
), by = .(codigo_municipio, ano)]

# 3. Abertura de dezembro por meio de acesso (categorias da Anatel: Fibra,
#    Cabo Metalico, Cabo Coaxial, Radio, Satelite; Hibrido/Outra em "outros").
#    Fica zero quando o municipio tem acessos em dezembro, mas nao por aquele meio.
meio_norm <- normalizar_nome(dezembro$meio)
dezembro[, meio := fcase(grepl("fibra", meio_norm), "acessos_fibra",
                         grepl("metalic", meio_norm), "acessos_cabo_metalico",
                         grepl("coaxial", meio_norm), "acessos_cabo_coaxial",
                         grepl("radio", meio_norm), "acessos_radio",
                         grepl("satelite", meio_norm), "acessos_satelite",
                         default = "acessos_outros")]
dezembro <- dcast(dezembro[ano %in% anual$ano], codigo_municipio + ano ~ meio,
                  value.var = "acessos", fun.aggregate = sum, fill = 0)
anual <- merge(anual, dezembro, by = c("codigo_municipio", "ano"), all.x = TRUE)
colunas_meio <- paste0("acessos_", c("fibra", "cabo_metalico", "cabo_coaxial", "radio", "satelite", "outros"))
for (v in colunas_meio) {
  if (!v %in% names(anual)) anual[, (v) := 0]
  anual[is.na(get(v)), (v) := 0]
}

# 4. Populacao: POPTOT (Censos e Contagem 2007) quando existe, senao ESTIMA_PO
#    (estimativas de 1o de julho). Ano sem nenhuma das duas series (ex.: 2023)
#    recebe a media simples dos anos vizinhos, quando ambos existem.
populacao <- rbindlist(lapply(c("POPTOT", "ESTIMA_PO"), function(serie) {
  arquivo <- file.path(dir_entrada, paste0("ipeadata_", serie, ".csv"))
  if (!file.exists(arquivo)) stop("Serie de populacao ausente: ", basename(arquivo), ". Execute o script 01 antes.")
  x <- as.data.table(ler_csv(arquivo))
  x[!is.na(valor) & !is.na(codigo_municipio), .(codigo_municipio = padronizar_codigo7(codigo_municipio),
                                                ano = as.integer(ano), serie = serie, valor = as.numeric(valor))]
}), use.names = TRUE)
populacao <- populacao[!is.na(codigo_municipio) & ano >= ANO_INICIAL - 1L]
populacao <- dcast(populacao, codigo_municipio + ano ~ serie, value.var = "valor",
                   fun.aggregate = function(v) v[length(v)], fill = NA_real_)
for (serie in c("POPTOT", "ESTIMA_PO")) if (!serie %in% names(populacao)) populacao[, (serie) := NA_real_]
populacao[, populacao := fcoalesce(POPTOT, ESTIMA_PO)]
grade <- CJ(codigo_municipio = unique(populacao$codigo_municipio), ano = seq(min(populacao$ano), max(populacao$ano)))
populacao <- merge(grade, populacao[, .(codigo_municipio, ano, populacao)], by = c("codigo_municipio", "ano"), all.x = TRUE)
setorder(populacao, codigo_municipio, ano)
populacao[, populacao := fifelse(is.na(populacao) & !is.na(shift(populacao)) & !is.na(shift(populacao, -1L)),
                                 (shift(populacao) + shift(populacao, -1L)) / 2, populacao), by = codigo_municipio]
populacao <- populacao[!is.na(populacao)]

# 5. Densidades, nome/UF oficiais e gravacao
anual <- merge(anual, populacao, by = c("codigo_municipio", "ano"), all.x = TRUE)
anual[, `:=`(densidade_banda_larga_100hab = 100 * acessos_banda_larga_fixa / populacao,
             densidade_media_100hab = 100 * acessos_media_mensal / populacao)]
sem_populacao <- anual[is.na(populacao), .N, by = ano]
if (nrow(sem_populacao)) log_msg("Aviso: municipio-ano sem populacao (densidade NA): ",
                                 paste0(sem_populacao$ano, "=", sem_populacao$N, collapse = ", "))
anual <- juntar_dicionario(anual, dicionario)
salvar_base_tratada(FONTE, anual)

URL_ANATEL <- "https://www.anatel.gov.br/dadosabertos/paineis_de_dados/acessos/acessos_banda_larga_fixa.zip"
salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("acessos_banda_larga_fixa", "acessos_media_mensal", "meses_informados", "acessos_fibra",
               "acessos_cabo_metalico", "acessos_cabo_coaxial", "acessos_radio", "acessos_satelite",
               "acessos_outros", "populacao", "densidade_banda_larga_100hab", "densidade_media_100hab"),
  descricao = c(
    "Acessos de banda larga fixa em servico em dezembro (todas as prestadoras e tecnologias)",
    "Media mensal dos acessos de banda larga fixa no ano (soma dos meses informados dividida pelo numero de meses)",
    "Numero de meses do ano publicados pela Anatel (4 em 2007-2010, 12 a partir de 2011)",
    "Acessos em dezembro por fibra optica",
    "Acessos em dezembro por cabo metalico (xDSL e similares)",
    "Acessos em dezembro por cabo coaxial (cable modem/HFC)",
    "Acessos em dezembro por radio (inclui Wi-Fi, FWA, WiMAX)",
    "Acessos em dezembro por satelite",
    "Acessos em dezembro por outros meios ou hibridos",
    "Populacao residente: Censos/Contagem (POPTOT) ou estimativa de 1o de julho (ESTIMA_PO) do Ipeadata; ano sem serie oficial (ex.: 2023) interpolado pela media dos anos vizinhos",
    "Acessos de banda larga fixa em dezembro por 100 habitantes",
    "Media mensal de acessos de banda larga fixa por 100 habitantes"
  ),
  unidade = c(rep("acessos", 2L), "meses", rep("acessos", 6L), "habitantes", rep("acessos por 100 habitantes", 2L)),
  periodicidade = "anual",
  tabela = "Acessos - Banda Larga Fixa (Anatel) + ESTIMA_PO/POPTOT (Ipeadata)",
  fonte_url = URL_ANATEL,
  stringsAsFactors = FALSE
))
