# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_vizinhos_municipios.R
# FONTE:  IBGE - malha municipal (via pacote geobr)
# OBJETIVO: Gerar a lista de adjacencia (municipios limitrofes) para TODO o
#           Brasil. Permite que a aplicacao ofereca comparacoes "municipio x
#           vizinhos" e agregacoes por entorno sem nenhuma lista pre-definida.
# SAIDA:  dados/auxiliares/vizinhos_municipios.csv
#         (codigo_municipio, codigo_vizinho, uf, uf_vizinho, compartilha_uf)
# DEPENDENCIAS: geobr, sf (instalacao opcional; ver instalar_dependencias.R).
# COMO EXECUTAR: Rscript fontes/00_comum/02_vizinhos_municipios.R
# ------------------------------------------------------------------------------

.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(.dir, "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("geobr", "sf"))

ANO_MALHA <- as.integer(Sys.getenv("PAINEL_ANO_MALHA", unset = "2022"))
destino <- file.path(DIR_AUXILIARES, "vizinhos_municipios.csv")

log_msg("Baixando a malha municipal ", ANO_MALHA, " (geobr).")
malha <- geobr::read_municipality(code_muni = "all", year = ANO_MALHA, showProgress = FALSE)
malha <- sf::st_transform(malha, 5880)  # SIRGAS 2000 / Brazil Polyconic
malha$codigo_municipio <- sprintf("%07d", as.integer(malha$code_muni))

log_msg("Calculando adjacencias entre ", nrow(malha), " poligonos.")
toques <- sf::st_touches(malha)
pares <- do.call(rbind, lapply(seq_along(toques), function(i) {
  if (!length(toques[[i]])) return(NULL)
  data.frame(codigo_municipio = malha$codigo_municipio[i],
             codigo_vizinho = malha$codigo_municipio[toques[[i]]],
             stringsAsFactors = FALSE)
}))
pares$uf <- uf_por_codigo(pares$codigo_municipio)
pares$uf_vizinho <- uf_por_codigo(pares$codigo_vizinho)
pares$compartilha_uf <- pares$uf == pares$uf_vizinho
pares <- pares[order(pares$codigo_municipio, pares$codigo_vizinho), ]

escrever_csv(pares, destino)
log_msg("Adjacencias gravadas: ", destino, " (", nrow(pares), " pares)")
registrar_execucao("vizinhos_municipios", "auxiliar", paste0(nrow(pares), " pares"))
