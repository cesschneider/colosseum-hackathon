# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_dicionario_municipios.R
# FONTE:  IBGE - API de localidades (lista oficial dos 5.570 municipios)
# OBJETIVO: Construir o dicionario territorial usado por TODAS as fontes:
#           codigo IBGE de 7 e 6 digitos, nome, UF, regiao, micro/mesorregiao e
#           regioes imediata/intermediaria. Substitui qualquer lista fixa de
#           municipios: o universo do painel e o Brasil inteiro.
# SAIDA:  dados/auxiliares/dicionario_municipios.csv
# COMO EXECUTAR: Rscript fontes/00_comum/01_dicionario_municipios.R
# ------------------------------------------------------------------------------

.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(.dir, "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()

dic <- construir_dicionario_municipios()
resumo <- table(dic$uf)
log_msg("Municipios por UF: ", paste(names(resumo), resumo, sep = "=", collapse = " "))
registrar_execucao("dicionario_municipios", "extracao", paste0(nrow(dic), " municipios"))
