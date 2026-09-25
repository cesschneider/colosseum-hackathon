# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_sim.R
# FONTE: Ministerio da Saude / DATASUS - Sistema de Informacoes sobre
#        Mortalidade (SIM-DO), microdados das declaracoes de obito
# OBJETIVO: Baixar, por UF e ano, os microdados de obitos (pacote microdatasus)
#           preservando apenas os campos necessarios aos indicadores, em um
#           RDS por UF-ano, com retomada (UF-ano ja gravado e pulado).
# COBERTURA: Brasil, 27 UFs (arquivos DO<UF><ANO>.dbc); 2000 ate o ultimo ano
#            publicado (definitivo ou preliminar).
# PERIODICIDADE: anual
# ENDPOINT: ftp://ftp.datasus.gov.br/dissemin/publicos/SIM/CID10/DORES/ (definitivos)
#           ftp://ftp.datasus.gov.br/dissemin/publicos/SIM/PRELIM/DORES/ (preliminares)
#           https://www.ipeadata.gov.br/api/odata4 (serie ESTIMA_PO, denominador das taxas)
# SAIDAS: dados/brutos/sim/sim_do_<UF>_<ano>[_preliminar].rds
#         dados/brutos/sim/ipeadata_estima_po.csv
# COMO EXECUTAR: Rscript fontes/sim/01_extracao_sim.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("microdatasus"))
FONTE <- "sim"

ANO_INICIAL <- ano_inicial_efetivo(2000L)
URL_FTP_SIM <- "ftp://ftp.datasus.gov.br/dissemin/publicos/SIM/"
# Campos estritamente necessarios: municipio de residencia, data do obito,
# idade codificada, sexo e causa basica (CID-10).
CAMPOS_SIM <- c("CODMUNRES", "DTOBITO", "IDADE", "SEXO", "CAUSABAS")
dir_saida <- dir_brutos(FONTE)

# ---- Funcoes ------------------------------------------------------------------

listar_ftp <- function(url) {
  # Nomes de arquivo de uma pasta do FTP do DATASUS (ex.: DOMG2024.dbc).
  h <- curl::new_handle()
  curl::handle_setopt(h, dirlistonly = TRUE, ftp_use_epsv = TRUE, timeout = 300L, connecttimeout = 60L)
  nomes <- strsplit(rawToChar(curl::curl_fetch_memory(url, handle = h)$content), "\\r?\\n")[[1L]]
  nomes[grepl("^DO[A-Z]{2}[0-9]{4}[.]dbc$", nomes, ignore.case = TRUE)]
}

nome_bruto <- function(uf, ano, preliminar) {
  file.path(dir_saida, sprintf("sim_do_%s_%d%s.rds", uf, ano, ifelse(preliminar, "_preliminar", "")))
}

gravar_rds <- function(x, destino) {
  temporario <- paste0(destino, ".part")
  saveRDS(x, temporario)
  if (file.exists(destino)) unlink(destino, force = TRUE)
  if (!file.rename(temporario, destino)) stop("Nao foi possivel gravar ", destino)
  invisible(destino)
}

baixar_ano <- function(ano, ufs) {
  # Uma chamada por ano com as UFs pendentes: o pacote lista as pastas do FTP,
  # baixa os .dbc, descompacta e devolve os campos pedidos como texto. A coluna
  # `source` (nome do .dbc, ex.: DOMG2024.dbc) identifica a UF de cada arquivo.
  dados <- microdatasus::fetch_datasus(
    year_start = ano, year_end = ano, uf = ufs, information_system = "SIM-DO",
    vars = CAMPOS_SIM, stop_on_error = FALSE, timeout = TIMEOUT_PADRAO,
    track_source = TRUE, quiet = TRUE
  )
  if (is.null(dados) || !nrow(dados)) return(list())
  dados <- as.data.frame(dados, stringsAsFactors = FALSE)
  faltando <- setdiff(CAMPOS_SIM, names(dados))
  if (length(faltando)) stop("Campos ausentes no SIM-DO ", ano, ": ", paste(faltando, collapse = ", "))
  split(dados[CAMPOS_SIM], toupper(substr(dados$source, 3L, 4L)))
}

# ---- 1. Descoberta dos arquivos publicados ---------------------------------------
# Definitivos (CID10/DORES) prevalecem sobre preliminares (PRELIM/DORES).
publicados <- rbind(
  data.frame(arquivo = listar_ftp(paste0(URL_FTP_SIM, "CID10/DORES/")), preliminar = FALSE, stringsAsFactors = FALSE),
  data.frame(arquivo = listar_ftp(paste0(URL_FTP_SIM, "PRELIM/DORES/")), preliminar = TRUE, stringsAsFactors = FALSE)
)
publicados$uf <- toupper(substr(publicados$arquivo, 3L, 4L))
publicados$ano <- as.integer(substr(publicados$arquivo, 5L, 8L))
publicados <- publicados[!duplicated(publicados[c("uf", "ano")]), ]
plano <- publicados[publicados$uf %in% UFS_ATIVAS$uf & publicados$ano >= ANO_INICIAL & publicados$ano <= ANO_ATUAL, ]
if (!nrow(plano)) stop("Nenhum arquivo SIM-DO publicado para as UFs/anos solicitados.")
plano$destino <- nome_bruto(plano$uf, plano$ano, plano$preliminar)
log_msg("SIM-DO publicado: ", min(plano$ano), "-", max(plano$ano), " (", nrow(plano), " arquivos UF-ano); ",
        "anos preliminares: ", paste(sort(unique(plano$ano[plano$preliminar])), collapse = ", "))

# ---- 2. Download por ano, com retomada -------------------------------------------
# Um UF-ano ja gravado e reutilizado. Um preliminar e substituido quando o
# DATASUS publica o definitivo (o arquivo _preliminar antigo e removido).
pendentes_total <- character()
for (ano in sort(unique(plano$ano))) {
  itens <- plano[plano$ano == ano, ]
  itens <- itens[!(REUTILIZAR_BRUTOS & file.exists(itens$destino)), ]
  if (!nrow(itens)) {
    log_msg("Reutilizado: ", ano, " (todas as UFs)")
    next
  }
  pendentes <- itens$uf
  for (tentativa in seq_len(TENTATIVAS_PADRAO)) {
    log_msg("Baixando SIM-DO ", ano, " (", tentativa, "/", TENTATIVAS_PADRAO, "): ", paste(pendentes, collapse = " "))
    partes <- tryCatch(baixar_ano(ano, pendentes), error = function(e) {
      log_msg("Erro no download de ", ano, ": ", conditionMessage(e))
      list()
    })
    for (uf in intersect(names(partes), pendentes)) {
      dados_uf <- partes[[uf]]
      if (!nrow(dados_uf)) next
      item <- itens[itens$uf == uf, ]
      gravar_rds(dados_uf, item$destino)
      if (!item$preliminar) unlink(nome_bruto(uf, ano, TRUE), force = TRUE)
      log_msg("Gravado: ", basename(item$destino), " (", nrow(dados_uf), " obitos)")
      pendentes <- setdiff(pendentes, uf)
    }
    if (!length(pendentes)) break
    if (tentativa < TENTATIVAS_PADRAO) Sys.sleep(min(2 ^ tentativa, 15))
  }
  if (length(pendentes)) pendentes_total <- c(pendentes_total, paste0(pendentes, "-", ano))
}

# ---- 3. Denominador das taxas: populacao estimada (Ipeadata, ESTIMA_PO) ----------
# Guardada junto aos brutos para que o script 02 rode sem acesso a rede.
arquivo_pop <- file.path(dir_saida, "ipeadata_estima_po.csv")
if (!REUTILIZAR_BRUTOS || !file.exists(arquivo_pop)) {
  log_msg("Baixando a serie ESTIMA_PO do Ipeadata.")
  tryCatch(escrever_csv(ipeadata_municipal("ESTIMA_PO"), arquivo_pop),
           error = function(e) log_msg("Aviso: falha ao baixar ESTIMA_PO (", conditionMessage(e), "). Rode de novo."))
} else {
  log_msg("Reutilizado: ", basename(arquivo_pop))
}

registrar_execucao(FONTE, "extracao", paste0(
  sum(file.exists(plano$destino)), " de ", nrow(plano), " arquivos UF-ano em ", dir_saida,
  if (length(pendentes_total)) paste0("; pendentes: ", paste(pendentes_total, collapse = ", ")) else ""
))
if (length(pendentes_total)) {
  stop("UF-ano nao baixados: ", paste(pendentes_total, collapse = ", "), ". Rode novamente para retomar.")
}
log_msg("Extracao concluida: ", dir_saida)
