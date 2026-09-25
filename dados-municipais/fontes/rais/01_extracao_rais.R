# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_rais.R
# FONTE: MTE/PDET - Microdados publicos da RAIS (estabelecimentos e vinculos)
# OBJETIVO: Descobrir no FTP oficial e baixar, sem descompactar, os arquivos
#           compactados de estabelecimentos e de vinculos de cada ano-base,
#           cobrindo todas as regioes do Brasil (ou so as UFs ativas em testes).
#           Cada arquivo baixado e validado com "7z t".
# COBERTURA: Brasil, todos os municipios; 2010 ate o ultimo ano-base publicado
# PERIODICIDADE: anual (posicao em 31/12 do ano-base; publicado no ano seguinte)
# ENDPOINT: ftp://ftp.mtps.gov.br/pdet/microdados/RAIS/<ano>/
# SAIDAS: dados/brutos/rais/<ano>/<nome original do arquivo no FTP>
# COMO EXECUTAR: Rscript fontes/rais/01_extracao_rais.R
#   Teste rapido: PAINEL_UFS="MG,ES" PAINEL_ANO_INICIAL=2023 (baixa so o preciso)
#   7-Zip fora do PATH: PAINEL_7Z="C:/caminho/7zr.exe"
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente()
FONTE <- "rais"

URL_FTP_RAIS <- "ftp://ftp.mtps.gov.br/pdet/microdados/RAIS"
# Espelho publico usado apenas como fallback (hoje contem somente o ano-base 2025).
URL_ESPELHO_RAIS <- "https://huggingface.co/datasets/selenelindsay/rais-caged-bronze/resolve/main/RAIS"
USAR_ESPELHO <- ler_booleano_env("PAINEL_RAIS_ESPELHO", TRUE)
ANO_INICIAL <- ano_inicial_efetivo(2010L)
ANO_FINAL <- as.integer(Sys.getenv("PAINEL_RAIS_ANO_FINAL", unset = ANO_ATUAL))
TIMEOUT_RAIS <- max(TIMEOUT_PADRAO, 7200L)   # arquivos de ate 1,1 GB por FTP
dir_saida <- dir_brutos(FONTE)

# Vinculos a partir de 2018 vem por regiao (RAIS_VINC_PUB_<REGIAO>.7z) e os
# estabelecimentos em RAIS_ESTAB_PUB.7z. Ate 2017 os vinculos vem por UF
# (<UF><ano>.7z) e os estabelecimentos em ESTB<ano>.7z (2002: Estb2002.zip).
# RAIS_VINC_PUB_NI.7z (UF nao identificada) nao e baixado: nao tem municipio.
REGIOES_RAIS <- list(
  CENTRO_OESTE = c("MS", "MT", "GO", "DF"),
  MG_ES_RJ = c("MG", "ES", "RJ"),
  NORDESTE = c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA"),
  NORTE = c("RO", "AC", "AM", "RR", "PA", "AP", "TO"),
  SP = "SP",
  SUL = c("PR", "SC", "RS")
)

localizar_7zip <- function() {
  # Ordem de busca: PAINEL_7Z, PATH (7z, 7za, 7zr) e pastas usuais do Windows.
  pastas <- c(Sys.getenv("ProgramFiles", "C:/Program Files"),
              Sys.getenv("ProgramFiles(x86)", "C:/Program Files (x86)"),
              file.path(Sys.getenv("LOCALAPPDATA", ""), "Programs"))
  candidatos <- c(Sys.getenv("PAINEL_7Z", unset = ""),
                  unname(Sys.which(c("7z", "7za", "7zr"))),
                  unlist(lapply(pastas, function(p) file.path(p, "7-Zip", c("7z.exe", "7zr.exe", "7za.exe")))))
  candidatos <- candidatos[nzchar(candidatos)]
  existentes <- candidatos[file.exists(candidatos)]
  if (!length(existentes)) {
    stop("7-Zip nao encontrado. Instale-o a partir de https://www.7-zip.org/download.html ",
         "(o 7zr.exe basta) e informe o caminho em PAINEL_7Z ou inclua-o no PATH.", call. = FALSE)
  }
  normalizePath(existentes[[1L]], winslash = "/", mustWork = FALSE)
}

testar_compactado <- function(arquivo, exe_7z) {
  # Integridade: "7z t" para .7z; para .zip (estabelecimentos de 2002) basta a
  # listagem do proprio R, pois o 7zr.exe nao le zip.
  if (!file.exists(arquivo) || file.info(arquivo)$size <= 0) return(FALSE)
  if (grepl("[.]zip$", arquivo, ignore.case = TRUE)) {
    membros <- suppressWarnings(tryCatch(utils::unzip(arquivo, list = TRUE), error = function(e) NULL))
    return(is.data.frame(membros) && nrow(membros) > 0L)
  }
  status <- suppressWarnings(system2(exe_7z, c("t", shQuote(arquivo)), stdout = FALSE, stderr = FALSE))
  identical(as.integer(status), 0L)
}

listar_ftp <- function(url) {
  # Itens de uma pasta do FTP: nome (ultimo campo da linha) e tamanho em bytes
  # (primeiro numero com 4+ digitos; vale para listagens no formato DOS e Unix).
  # A listagem chega em Latin-1 e e convertida antes de qualquer regex.
  texto <- iconv(obter_texto_url(url, timeout = 300L), from = "latin1", to = "UTF-8", sub = "?")
  linhas <- trimws(strsplit(texto, "\r?\n")[[1L]])
  linhas <- linhas[nzchar(linhas)]
  posicao <- regexpr("\\b[0-9]{4,}\\b", linhas, perl = TRUE)
  tamanho <- rep(NA_real_, length(linhas))
  tamanho[posicao > 0L] <- as.numeric(regmatches(linhas, posicao))
  data.frame(nome = sub("^.*[[:space:]]", "", linhas), tamanho = tamanho, stringsAsFactors = FALSE)
}

exe_7z <- localizar_7zip()
log_msg("7-Zip: ", exe_7z)

# 1. Anos-base publicados: pastas AAAA do FTP ("2023 Parcial", "Layouts" e as
#    subpastas com versoes anteriores ficam de fora).
raiz <- listar_ftp(paste0(URL_FTP_RAIS, "/"))
anos <- sort(as.integer(raiz$nome[grepl("^[0-9]{4}$", raiz$nome)]))
anos <- anos[anos >= ANO_INICIAL & anos <= ANO_FINAL]
if (!length(anos)) stop("Nenhum ano-base entre ", ANO_INICIAL, " e ", ANO_FINAL, " em ", URL_FTP_RAIS)
log_msg("Anos-base a coletar: ", min(anos), "-", max(anos), " (", length(anos), " anos)")

# 2. Plano de coleta: por ano, o arquivo de estabelecimentos e os arquivos de
#    vinculos das regioes/UFs que contem alguma UF ativa.
ufs <- UFS_ATIVAS$uf
regioes <- names(REGIOES_RAIS)[vapply(REGIOES_RAIS, function(u) any(u %in% ufs), logical(1L))]
montar_plano <- function(ano) {
  itens <- listar_ftp(paste0(URL_FTP_RAIS, "/", ano, "/"))
  nome <- toupper(itens$nome)
  estab <- nome == "RAIS_ESTAB_PUB.7Z" | grepl(paste0("^ESTB", ano, "[.](7Z|ZIP)$"), nome)
  vinc <- nome %in% c(paste0("RAIS_VINC_PUB_", regioes, ".7Z"), paste0(ufs, ano, ".7Z"))
  if (!any(estab) || !any(vinc)) {
    log_msg("Aviso: ", ano, " sem arquivos reconhecidos de estabelecimentos e vinculos; ano ignorado.")
    return(NULL)
  }
  escolhidos <- estab | vinc
  data.frame(ano = ano, nome = itens$nome[escolhidos], tipo = ifelse(estab[escolhidos], "estab", "vinc"),
             tamanho_remoto = itens$tamanho[escolhidos], stringsAsFactors = FALSE)
}
plano <- do.call(rbind, lapply(anos, montar_plano))
if (is.null(plano) || !nrow(plano)) stop("Plano de coleta vazio: nenhum arquivo reconhecido no FTP.")
plano$url <- paste0(URL_FTP_RAIS, "/", plano$ano, "/", plano$nome)
plano$destino <- file.path(dir_saida, plano$ano, plano$nome)
log_msg(nrow(plano), " arquivos no plano; volume remoto de ",
        round(sum(plano$tamanho_remoto, na.rm = TRUE) / 1024^3, 1), " GB")

# 3. Download atomico com reutilizacao: um arquivo local e reaproveitado quando
#    tem exatamente o tamanho publicado no FTP (republicacoes, como o segundo
#    processamento da RAIS 2024, mudam o tamanho e sao rebaixadas sozinhas).
#    So os arquivos baixados nesta execucao passam pelo "7z t" (demorado).
inicio <- Sys.time()
baixados <- 0L
for (i in seq_len(nrow(plano))) {
  p <- plano[i, ]
  tamanho_ok <- function(f) {
    tamanho <- file.info(f)$size
    isTRUE(tamanho > 0) && (is.na(p$tamanho_remoto) || isTRUE(tamanho == p$tamanho_remoto))
  }
  reutilizar <- REUTILIZAR_BRUTOS && file.exists(p$destino) && tamanho_ok(p$destino)
  log_msg("[", i, "/", nrow(plano), "] ", p$ano, " ", p$nome, " (", round(p$tamanho_remoto / 1024^2), " MB)")
  urls <- p$url
  if (USAR_ESPELHO) urls <- c(urls, paste0(URL_ESPELHO_RAIS, "/", p$ano, "/", p$nome, "?download=true"))
  erros <- character()
  for (url in urls) {
    resultado <- tryCatch({
      baixar_arquivo(url, p$destino, reutilizar = reutilizar, timeout = TIMEOUT_RAIS, validador = tamanho_ok)
      TRUE
    }, error = function(e) conditionMessage(e))
    if (isTRUE(resultado)) break
    erros <- c(erros, resultado)
  }
  if (!isTRUE(resultado)) stop("Falha ao obter ", p$nome, " (", p$ano, "):\n", paste(erros, collapse = "\n"))
  if (!reutilizar) {
    if (!testar_compactado(p$destino, exe_7z)) {
      unlink(p$destino, force = TRUE)
      stop("Arquivo corrompido (teste do 7-Zip falhou) e removido: ", p$destino, ". Execute novamente.")
    }
    baixados <- baixados + 1L
  }
}

minutos <- round(as.numeric(difftime(Sys.time(), inicio, units = "mins")), 1)
log_msg("Extracao concluida: ", nrow(plano), " arquivos (", baixados, " baixados, ",
        nrow(plano) - baixados, " reutilizados) em ", minutos, " min.")
registrar_execucao(FONTE, "extracao", paste0(nrow(plano), " arquivos (", baixados, " baixados) em ", dir_saida))
