# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_<fonte>.R   (MODELO - copie e adapte)
# FONTE: <orgao> - <conjunto de dados>
# OBJETIVO: Ler os brutos, padronizar codigos/periodos e gravar a base
#           municipal no esquema do painel (uma linha por municipio-periodo).
# ENTRADAS: dados/brutos/<fonte>/...
# SAIDAS: dados/tratados/<fonte>/<fonte>_municipal.csv
#         dados/tratados/<fonte>/<fonte>_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/<fonte>/02_tratamento_<fonte>.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table"))
library(data.table)
FONTE <- "<fonte>"

dicionario <- carregar_dicionario_municipios()
arquivos <- list.files(dir_brutos(FONTE), pattern = "[.]csv$", full.names = TRUE)
if (!length(arquivos)) stop("Nenhum bruto encontrado. Execute o script 01 antes.")

# 1. Leitura e empilhamento
bruto <- rbindlist(lapply(arquivos, function(a) fread(a, encoding = "UTF-8")), fill = TRUE)

# 2. Padronizacao de chaves (exemplos)
bruto[, codigo_municipio := padronizar_codigo7(codigo)]          # 7 digitos
# bruto[, codigo_municipio := codigo6_para_7(codigo6, dicionario)] # se a fonte usa 6 digitos
bruto[, ano := as.integer(ano)]

# 3. Agregacao para municipio-ano e calculo de indicadores
base <- bruto[!is.na(codigo_municipio), .(
  indicador_a = sum(valor_a, na.rm = TRUE),
  indicador_b = mean(valor_b, na.rm = TRUE)
), by = .(codigo_municipio, ano)]

# 4. Nome/UF oficiais e gravacao
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("indicador_a", "indicador_b"),
  descricao = c("Descricao do indicador A", "Descricao do indicador B"),
  unidade = c("unidades", "R$ correntes"),
  periodicidade = "anual",
  fonte_url = "https://exemplo.gov.br",
  stringsAsFactors = FALSE
))
