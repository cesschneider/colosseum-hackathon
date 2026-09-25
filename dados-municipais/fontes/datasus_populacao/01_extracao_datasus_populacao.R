# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_datasus_populacao.R
# FONTE: DataSUS/TabNet - Populacao residente: estimativas populacionais por
#        municipio, idade e sexo (estudo MS/SVSA-RIPSA; formulario
#        ibge/cnv/popsvs<edicao>br.def)
# OBJETIVO: Descobrir a edicao e os anos publicados e baixar, ano a ano, a
#           tabela de populacao por municipio e faixa etaria (formato .prn),
#           preservando a resposta bruta do TabNet sem transformar.
# COBERTURA: Brasil, todos os municipios; 2000 ate o ano mais recente publicado.
# PERIODICIDADE: anual
# ENDPOINT: http://tabnet.datasus.gov.br/cgi/deftohtm.exe?ibge/cnv/popsvs2024br.def
#           (consulta: POST em http://tabnet.datasus.gov.br/cgi/tabcgi.exe?ibge/cnv/popsvs2024br.def)
# SAIDAS: dados/brutos/datasus_populacao/datasus_populacao_faixa_etaria_<ano>.html
# COMO EXECUTAR: Rscript fontes/datasus_populacao/01_extracao_datasus_populacao.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "datasus_populacao"

ANO_INICIAL <- ano_inicial_efetivo(2000L)
URL_CGI_TABNET <- "http://tabnet.datasus.gov.br/cgi/"
EDICAO_MINIMA <- 2024L   # primeira edicao do estudo publicada neste formulario
TIMEOUT_TABNET <- 600L
dir_saida <- dir_brutos(FONTE)

# ---- Funcoes ------------------------------------------------------------------

ler_latin1 <- function(bytes) iconv(rawToChar(bytes), from = "latin1", to = "UTF-8")

descobrir_formulario <- function() {
  # O TabNet publica um .def por edicao do estudo (popsvs2024br.def cobre
  # 2000-2025). Tenta as edicoes mais novas primeiro; as inexistentes
  # respondem HTTP 200 com "Arquivo DEF nao encontrado".
  for (edicao in rev(seq(EDICAO_MINIMA, ANO_ATUAL + 1L))) {
    url <- paste0(URL_CGI_TABNET, "deftohtm.exe?ibge/cnv/popsvs", edicao, "br.def")
    texto <- tryCatch(iconv(obter_texto_url(url, timeout = TIMEOUT_TABNET), from = "latin1", to = "UTF-8"),
                      error = function(e) "")
    if (grepl('VALUE="pop[0-9]{2}[.]dbf"', texto, ignore.case = TRUE)) {
      log_msg("Edicao do estudo encontrada: popsvs", edicao, "br.def")
      return(list(edicao = edicao, texto = texto,
                  url_consulta = sub("deftohtm[.]exe", "tabcgi.exe", url)))
    }
  }
  stop("Nenhuma edicao do formulario popsvs<edicao>br.def foi encontrada no TabNet.")
}

descobrir_anos <- function(texto) {
  # Cada ano e uma <OPTION VALUE="popAA.dbf">AAAA do campo "Arquivos".
  padrao <- '<OPTION[[:space:]]+VALUE="(pop[0-9]{2}[.]dbf)"[^>]*>[[:space:]]*(20[0-9]{2})'
  trechos <- regmatches(texto, gregexpr(padrao, texto, perl = TRUE, ignore.case = TRUE))[[1L]]
  if (!length(trechos)) stop("Nao foi possivel descobrir os anos no formulario do TabNet.")
  plano <- data.frame(
    arquivo_dbf = sub(padrao, "\\1", trechos, perl = TRUE, ignore.case = TRUE),
    ano = as.integer(sub(padrao, "\\2", trechos, perl = TRUE, ignore.case = TRUE)),
    stringsAsFactors = FALSE
  )
  plano <- plano[!duplicated(plano$ano), ]
  plano[order(plano$ano), ]
}

montar_corpo <- function(arquivo_dbf) {
  # O CGI espera os nomes dos campos em latin1: os escapes percentuais sao
  # deliberados (enviar UTF-8 gera "Tabela de conversao nao encontrada").
  # Regiao, UF, municipio, sexo e faixa em TODAS_AS_CATEGORIAS = Brasil inteiro,
  # linhas = municipio, colunas = Faixa Etaria 1, formato .prn.
  paste0(
    "Linha=Munic%EDpio", "&Coluna=Faixa_Et%E1ria_1", "&Incremento=Popula%E7%E3o_residente",
    "&Arquivos=", arquivo_dbf,
    "&SRegi%E3o=TODAS_AS_CATEGORIAS__", "&SUnidade_da_Federa%E7%E3o=TODAS_AS_CATEGORIAS__",
    "&SMunic%EDpio=TODAS_AS_CATEGORIAS__", "&SSexo=TODAS_AS_CATEGORIAS__",
    "&SFaixa_Et%E1ria_1=TODAS_AS_CATEGORIAS__", "&formato=prn&mostre=Mostra"
  )
}

consultar_tabnet <- function(url, corpo) {
  # A biblioteca comum so faz GET; o TabNet exige POST com corpo url-encoded.
  h <- curl::new_handle()
  curl::handle_setopt(h, post = TRUE, postfields = charToRaw(corpo), timeout = TIMEOUT_TABNET,
                      connecttimeout = 60L, followlocation = TRUE)
  curl::handle_setheaders(h, `Content-Type` = "application/x-www-form-urlencoded",
                          `User-Agent` = USER_AGENT, Accept = "*/*")
  resposta <- curl::curl_fetch_memory(url, handle = h)
  if (resposta$status_code != 200L) stop("HTTP ", resposta$status_code, " na consulta ao TabNet")
  resposta$content
}

problema_resposta <- function(arquivo, ano) {
  # Devolve NULL se o arquivo e a tabela esperada ou a descricao do problema.
  # Toda divergencia (inclusive periodo diferente do pedido) e bloqueante.
  tamanho <- file.info(arquivo)$size
  if (is.na(tamanho) || tamanho < 100000) return("resposta vazia ou pequena demais")
  texto <- ler_latin1(readBin(arquivo, "raw", tamanho))
  if (grepl("Tabela de convers|Internal Server Error|Service Unavailable|<h1>ERRO", texto, ignore.case = TRUE)) {
    return("pagina de erro do TabNet")
  }
  if (!grepl("<PRE>", texto, fixed = TRUE) || !grepl('"0 a 4 anos"', texto, fixed = TRUE) ||
      !grepl('"80 anos e mais"', texto, fixed = TRUE)) {
    return("tabela por faixa etaria nao encontrada")
  }
  if (!grepl(paste0("odo:</b>[[:space:]]*", ano, "([^0-9]|$)"), texto)) {
    return(paste("periodo da resposta diferente de", ano))
  }
  n_municipios <- sum(grepl('^"[0-9]{6} ', strsplit(texto, "\\r?\\n")[[1L]]))
  if (n_municipios < 5500L) return(paste("apenas", n_municipios, "linhas municipais"))
  NULL
}

substituir_arquivo <- function(temporario, destino) {
  # O bruto anterior so sai depois de o novo arquivo (ja validado) estar no lugar.
  backup <- paste0(destino, ".bak")
  if (file.exists(destino) && !file.rename(destino, backup)) stop("Nao foi possivel reservar ", destino)
  if (!file.rename(temporario, destino)) {
    if (file.exists(backup)) file.rename(backup, destino)
    stop("Nao foi possivel gravar ", destino)
  }
  if (file.exists(backup)) unlink(backup, force = TRUE)
  invisible(destino)
}

# ---- 1. Plano de coleta ---------------------------------------------------------
formulario <- descobrir_formulario()
plano <- descobrir_anos(formulario$texto)
plano <- plano[plano$ano >= ANO_INICIAL, ]
if (!nrow(plano)) stop("Nenhum ano publicado a partir de ", ANO_INICIAL, ".")
ano_mais_recente <- max(plano$ano)
plano$destino <- file.path(dir_saida, sprintf("datasus_populacao_faixa_etaria_%d.html", plano$ano))
log_msg("Anos publicados: ", min(plano$ano), "-", ano_mais_recente, " (", nrow(plano), " consultas)")

# ---- 2. Consulta ano a ano, com retomada ----------------------------------------
# Anos encerrados sao reutilizados quando o bruto local e valido; o ano mais
# recente e sempre consultado de novo (pode ser revisado ate a proxima edicao).
falhas <- integer()
for (i in seq_len(nrow(plano))) {
  ano <- plano$ano[i]
  destino <- plano$destino[i]
  if (REUTILIZAR_BRUTOS && ano < ano_mais_recente && file.exists(destino) &&
      is.null(problema_resposta(destino, ano))) {
    log_msg("Reutilizado: ", basename(destino))
    next
  }
  temporario <- paste0(destino, ".part")
  problema <- "nao consultado"
  for (tentativa in seq_len(TENTATIVAS_PADRAO)) {
    log_msg("Consultando TabNet (", tentativa, "/", TENTATIVAS_PADRAO, "): ", ano, " - ", plano$arquivo_dbf[i])
    problema <- tryCatch({
      writeBin(consultar_tabnet(formulario$url_consulta, montar_corpo(plano$arquivo_dbf[i])), temporario)
      problema_resposta(temporario, ano)
    }, error = function(e) conditionMessage(e))
    if (is.null(problema)) break
    log_msg("Falha em ", ano, ": ", problema)
    if (tentativa < TENTATIVAS_PADRAO) Sys.sleep(min(2 ^ tentativa, 15))
  }
  if (is.null(problema)) {
    substituir_arquivo(temporario, destino)
  } else {
    unlink(temporario, force = TRUE)
    falhas <- c(falhas, ano)
  }
  Sys.sleep(1)   # pausa curta entre consultas ao servidor publico
}

registrar_execucao(FONTE, "extracao", paste0(
  nrow(plano) - length(falhas), " de ", nrow(plano), " anos em ", dir_saida,
  if (length(falhas)) paste0("; falhas: ", paste(falhas, collapse = ", ")) else ""
))
if (length(falhas)) {
  stop("Consulta ao TabNet falhou para: ", paste(falhas, collapse = ", "), ". Rode novamente para completar.")
}
log_msg("Extracao concluida: ", dir_saida)
