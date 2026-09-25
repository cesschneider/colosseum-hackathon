# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_anp.R
# FONTE: ANP - Dados abertos: vendas anuais de combustiveis por municipio e
#        Levantamento de Precos de Combustiveis (serie historica semestral)
# OBJETIVO: Ler os brutos e gravar duas bases municipais: vendas por produto
#           (municipio-ano) e preco medio de revenda por produto
#           (municipio-mes, apenas municipios pesquisados).
# ENTRADAS: dados/brutos/anp/vendas/vendas_<produto>.csv
#           dados/brutos/anp/precos/precos_<ca|glp>_<ano>_<semestre>.zip|csv
# SAIDAS: dados/tratados/anp/anp_vendas_municipal.csv
#         dados/tratados/anp/anp_precos_municipal.csv
#         dados/tratados/anp/anp_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/anp/02_tratamento_anp.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table"))
library(data.table)
FONTE <- "anp"

URL_VENDAS <- "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/vendas-de-derivados-de-petroleo-e-biocombustiveis"
URL_PRECOS <- "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/serie-historica-de-precos-de-combustiveis"
ANO_INICIAL_VENDAS <- ano_inicial_efetivo(1990L)
ANO_INICIAL_PRECOS <- ano_inicial_efetivo(2013L)
dicionario <- carregar_dicionario_municipios()

# Produto (nome do arquivo) -> variavel. Os CSVs trazem litros; o painel grava
# m3 (/1000). GLP vem em kg (P13 = botijoes de 13 kg; OUTROS = demais).
VARIAVEIS_VENDAS <- c(
  "etanol-hidratado" = "vendas_etanol_hidratado_m3", "gasolina-c" = "vendas_gasolina_c_m3",
  "oleo-diesel" = "vendas_oleo_diesel_m3", "oleo-combustivel" = "vendas_oleo_combustivel_m3",
  "gasolina-de-aviacao" = "vendas_gasolina_aviacao_m3", "querosene-de-aviacao" = "vendas_querosene_aviacao_m3",
  "querosene-iluminante" = "vendas_querosene_iluminante_m3", "asfalto" = "vendas_asfalto_m3"
)
# Produto do levantamento de precos -> sufixo da variavel (grafias antigas incluidas).
PRODUTOS_PRECOS <- c(
  "GASOLINA" = "gasolina", "GASOLINA ADITIVADA" = "gasolina_aditivada", "ETANOL" = "etanol", "ALCOOL" = "etanol",
  "DIESEL" = "diesel", "OLEO DIESEL" = "diesel", "DIESEL S10" = "diesel_s10", "OLEO DIESEL S10" = "diesel_s10",
  "GNV" = "gnv", "GAS NATURAL VEICULAR" = "gnv", "GLP" = "glp_p13"
)

casar_municipios <- function(chaves) {
  # chaves: data.table(uf, municipio) unicas -> codigo_municipio.
  # 1) nome normalizado + UF (biblioteca); 2) variantes de grafia dentro da
  # mesma UF: nomes truncados (prefixo) e diferencas de ate 1-2 caracteres
  # (ex.: SANTANA DO LIVRAMENTO / Sant'Ana do Livramento), so com candidato unico.
  chaves <- as.data.table(juntar_por_nome_uf(as.data.frame(chaves), "municipio", "uf", dicionario))
  pendentes <- which(is.na(chaves$codigo_municipio) & chaves$uf %in% dicionario$uf)
  for (i in pendentes) {
    nome <- normalizar_nome(chaves$municipio[i])
    cand <- dicionario[dicionario$uf == chaves$uf[i], ]
    if (nchar(chaves$municipio[i]) >= 30L) {
      achado <- which(startsWith(cand$nome_normalizado, nome))
    } else {
      dist <- utils::adist(nome, cand$nome_normalizado)[1L, ]
      achado <- which(dist == min(dist) & dist <= (if (nchar(nome) >= 10L) 2L else 1L))
    }
    if (length(achado) == 1L) set(chaves, i, "codigo_municipio", cand$codigo_municipio[achado])
  }
  sem <- chaves[is.na(codigo_municipio), paste(municipio, uf)]
  log_msg("Chaves municipio+UF apos variantes: ", nrow(chaves) - length(sem), " de ", nrow(chaves),
          " casadas. Sem correspondencia: ", paste(head(sem, 15L), collapse = " | "))
  chaves
}

soma_ou_na <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

# ---- 1. Vendas anuais por municipio ------------------------------------------
ler_vendas <- function(arquivo) {
  produto <- sub("^vendas_(.*)[.]csv$", "\\1", basename(arquivo))
  d <- fread(arquivo, sep = ";", encoding = "UTF-8", colClasses = "character", fill = TRUE)
  setnames(d, normalizar_nome(names(d)))
  if (!all(c("ano", "uf", "codigo ibge", "municipio") %in% names(d))) {
    log_msg("Layout nao reconhecido, arquivo ignorado: ", basename(arquivo))
    return(NULL)
  }
  base <- d[, .(ano = as.integer(ano), uf = toupper(trimws(uf)), codigo_ibge = padronizar_codigo7(`codigo ibge`),
                municipio = trimws(municipio))]
  if (produto == "glp" && all(c("p13", "outros") %in% names(d))) {
    p13 <- para_numero(d$p13); outros <- para_numero(d$outros)
    total <- fcoalesce(p13, 0) + fcoalesce(outros, 0)
    total[is.na(p13) & is.na(outros)] <- NA_real_
    longo <- rbind(cbind(base, variavel = "vendas_glp_p13_kg", valor = p13),
                   cbind(base, variavel = "vendas_glp_kg", valor = total))
  } else if (produto %in% names(VARIAVEIS_VENDAS) && "vendas" %in% names(d)) {
    longo <- cbind(base, variavel = VARIAVEIS_VENDAS[[produto]], valor = para_numero(d$vendas) / 1000)
  } else {
    log_msg("Produto/colunas nao reconhecidos, arquivo ignorado: ", basename(arquivo))
    return(NULL)
  }
  longo[!is.na(ano) & ano >= ANO_INICIAL_VENDAS & !is.na(valor)]
}

arquivos_vendas <- list.files(dir_brutos(FONTE, "vendas"), pattern = "^vendas_.*[.]csv$", full.names = TRUE)
if (length(arquivos_vendas)) {
  vendas <- rbindlist(lapply(arquivos_vendas, function(a) {
    log_msg("Lendo ", basename(a))
    ler_vendas(a)
  }))
  if (!nrow(vendas)) stop("Nenhum arquivo de vendas pode ser lido.")
  # Codigo IBGE do arquivo quando valido e coerente com a UF (anos antigos trazem
  # codigos fora do padrao); caso contrario, casamento por nome + UF.
  vendas[, codigo_municipio := fifelse(codigo_ibge %in% dicionario$codigo_municipio &
                                         uf == uf_por_codigo(codigo_ibge), codigo_ibge, NA_character_)]
  pendentes <- vendas[is.na(codigo_municipio), unique(.SD), .SDcols = c("uf", "municipio")]
  if (nrow(pendentes)) {
    pendentes <- casar_municipios(pendentes)[, .(uf, municipio, codigo_nome = codigo_municipio)]
    vendas <- merge(vendas, pendentes, by = c("uf", "municipio"), all.x = TRUE)
    vendas[is.na(codigo_municipio), codigo_municipio := codigo_nome]
  }
  perdidas <- sum(is.na(vendas$codigo_municipio))
  log_msg("Vendas: ", perdidas, " de ", nrow(vendas), " linhas descartadas sem codigo IBGE (",
          round(100 * perdidas / nrow(vendas), 2), "%)")
  vendas <- vendas[!is.na(codigo_municipio), .(valor = soma_ou_na(valor)), by = .(codigo_municipio, ano, variavel)]
  totais <- vendas[ano == max(ano), .(total = round(sum(valor, na.rm = TRUE))), by = variavel]
  log_msg("Totais nacionais no ultimo ano (conferencia de unidade): ",
          paste(totais$variavel, totais$total, sep = "=", collapse = "; "))
  vendas_largo <- dcast(vendas, codigo_municipio + ano ~ variavel, value.var = "valor")
  vendas_largo <- juntar_dicionario(vendas_largo, dicionario)
  salvar_base_tratada(FONTE, vendas_largo, nome = "anp_vendas_municipal")
} else {
  log_msg("Sem brutos de vendas; base anp_vendas_municipal nao gerada.")
}

# ---- 2. Precos de revenda: media mensal por municipio e produto ----------------
ler_precos <- function(arquivo) {
  csv <- arquivo
  if (grepl("[.]zip$", arquivo)) {
    pasta <- tempfile("anp_precos_")
    on.exit(unlink(pasta, recursive = TRUE), add = TRUE)
    descompactar_zip(arquivo, pasta)
    csv <- list.files(pasta, pattern = "[.]csv$", full.names = TRUE, recursive = TRUE, ignore.case = TRUE)[1L]
  }
  cabecalho <- normalizar_nome(names(fread(csv, sep = ";", nrows = 0L, encoding = "UTF-8")))
  colunas <- match(c("estado sigla", "municipio", "produto", "data da coleta", "valor de venda"), cabecalho)
  if (anyNA(colunas)) {
    log_msg("Layout nao reconhecido, arquivo ignorado: ", basename(arquivo), " (", paste(cabecalho, collapse = " | "), ")")
    return(NULL)
  }
  d <- fread(csv, sep = ";", select = colunas, colClasses = "character", encoding = "UTF-8")
  setnames(d, c("uf", "municipio", "produto", "data", "valor"))
  iso <- grepl("^[0-9]{4}-", d$data)
  d[, `:=`(uf = toupper(trimws(uf)), municipio = trimws(municipio),
           produto = unname(PRODUTOS_PRECOS[toupper(remover_acentos(trimws(produto)))]),
           ano = as.integer(ifelse(iso, substr(data, 1L, 4L), substr(data, 7L, 10L))),
           mes = as.integer(ifelse(iso, substr(data, 6L, 7L), substr(data, 4L, 5L))),
           valor = para_numero(valor))]
  d <- d[!is.na(produto) & !is.na(ano) & !is.na(mes) & !is.na(valor) & valor > 0 & ano >= ANO_INICIAL_PRECOS]
  d[, .(soma = sum(valor), n = .N), by = .(uf, municipio, ano, mes, produto)]
}

arquivos_precos <- list.files(dir_brutos(FONTE, "precos"), pattern = "^precos_(ca|glp)_[0-9]{4}_0[12][.](zip|csv)$",
                              full.names = TRUE)
if (length(arquivos_precos)) {
  precos <- rbindlist(lapply(arquivos_precos, function(a) {
    log_msg("Lendo ", basename(a))
    ler_precos(a)
  }))
  if (!nrow(precos)) stop("Nenhum arquivo de precos pode ser lido.")
  precos <- precos[, .(soma = sum(soma), n = sum(n)), by = .(uf, municipio, ano, mes, produto)]
  chaves <- casar_municipios(unique(precos[, .(uf, municipio)]))
  precos <- merge(precos, chaves[, .(uf, municipio, codigo_municipio)], by = c("uf", "municipio"), all.x = TRUE)
  perdidas <- precos[is.na(codigo_municipio), sum(n)]
  log_msg("Precos: ", perdidas, " de ", sum(precos$n), " coletas descartadas sem codigo IBGE (",
          round(100 * perdidas / sum(precos$n), 2), "%)")
  precos <- precos[!is.na(codigo_municipio), .(soma = sum(soma), n = sum(n)), by = .(codigo_municipio, ano, mes, produto)]
  precos[, media := soma / n]
  precos_largo <- dcast(precos, codigo_municipio + ano + mes ~ produto, value.var = "media")
  setnames(precos_largo, setdiff(names(precos_largo), c("codigo_municipio", "ano", "mes")),
           paste0("preco_medio_", setdiff(names(precos_largo), c("codigo_municipio", "ano", "mes"))))
  for (v in paste0("preco_medio_", unique(PRODUTOS_PRECOS))) if (!v %in% names(precos_largo)) precos_largo[, (v) := NA_real_]
  precos_largo <- merge(precos_largo, precos[, .(n_coletas_total = sum(n)), by = .(codigo_municipio, ano, mes)],
                        by = c("codigo_municipio", "ano", "mes"))
  precos_largo <- juntar_dicionario(precos_largo, dicionario)
  salvar_base_tratada(FONTE, precos_largo, nome = "anp_precos_municipal", mensal = TRUE)
} else {
  log_msg("Sem brutos de precos; base anp_precos_municipal nao gerada.")
}

# ---- 3. Dicionario de variaveis (as duas bases) --------------------------------
dic_vendas <- data.frame(
  tabela = "anp_vendas_municipal",
  variavel = c(unname(VARIAVEIS_VENDAS), "vendas_glp_kg", "vendas_glp_p13_kg"),
  descricao = c("Vendas de etanol hidratado pelas distribuidoras no municipio",
                "Vendas de gasolina C", "Vendas de oleo diesel", "Vendas de oleo combustivel",
                "Vendas de gasolina de aviacao", "Vendas de querosene de aviacao", "Vendas de querosene iluminante",
                "Vendas de asfalto", "Vendas de GLP, todos os vasilhames (P13 + outros)",
                "Vendas de GLP em botijoes de 13 kg (P13)"),
  unidade = c(rep("m3", length(VARIAVEIS_VENDAS)), "kg", "kg"),
  periodicidade = "anual", fonte_url = URL_VENDAS, stringsAsFactors = FALSE
)
dic_precos <- data.frame(
  tabela = "anp_precos_municipal",
  variavel = c(paste0("preco_medio_", unique(PRODUTOS_PRECOS)), "n_coletas_total"),
  descricao = c("Preco medio de venda ao consumidor - gasolina comum", "Preco medio de venda - gasolina aditivada",
                "Preco medio de venda - etanol hidratado", "Preco medio de venda - diesel (S500)",
                "Preco medio de venda - diesel S10", "Preco medio de venda - GNV",
                "Preco medio de venda - GLP botijao de 13 kg",
                "Numero de coletas de preco (postos x semanas x produtos) no municipio-mes"),
  unidade = c(rep("R$ por litro (nominal)", 5L), "R$ por m3 (nominal)", "R$ por 13 kg (nominal)", "coletas"),
  periodicidade = "mensal", fonte_url = URL_PRECOS, stringsAsFactors = FALSE
)
salvar_dicionario_variaveis(FONTE, rbind(dic_vendas, dic_precos))
