# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_rais.R
# FONTE: MTE/PDET - Microdados publicos da RAIS (estabelecimentos e vinculos)
# OBJETIVO: Ler os arquivos compactados em fluxo ("7z x -so" canalizado para o
#           R, sem descompactar em disco), agregar por municipio-ano e setor
#           (IBGE subsetor) e gravar a base municipal: estabelecimentos,
#           vinculos ativos em 31/12, massa salarial e remuneracao media de
#           dezembro (valores nominais) e taxa de ocupacao.
# ENTRADAS: dados/brutos/rais/<ano>/*.7z (script 01); populacao do Ipeadata
#           (serie ESTIMA_PO) para a taxa de ocupacao.
# SAIDAS: dados/brutos/rais/parciais/rais_<ano>.csv (agregado por ano; retomada)
#         dados/tratados/rais/rais_municipal.csv
#         dados/tratados/rais/rais_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/rais/02_tratamento_rais.R
#   Teste rapido: PAINEL_UFS="MG,ES" PAINEL_ANO_INICIAL=2023
#   PAINEL_RAIS_REPROCESSAR=TRUE ignora as parciais; PAINEL_RAIS_BLOCO=<linhas>
#   PAINEL_RAIS_ANO_BASE_REAIS=2024 acrescenta colunas *_reais_2024 (IPCA)
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table"))
library(data.table)
FONTE <- "rais"

URL_FONTE <- "ftp://ftp.mtps.gov.br/pdet/microdados/RAIS/"
ANO_INICIAL <- ano_inicial_efetivo(2010L)
TAMANHO_BLOCO <- max(10000L, as.integer(Sys.getenv("PAINEL_RAIS_BLOCO", unset = "500000")))
REPROCESSAR <- ler_booleano_env("PAINEL_RAIS_REPROCESSAR", FALSE)
ANO_BASE_REAIS <- suppressWarnings(as.integer(Sys.getenv("PAINEL_RAIS_ANO_BASE_REAIS", unset = "")))
SETORES <- c("industria", "construcao_civil", "comercio", "servicos", "agropecuaria", "nao_classificado")
MEDIDAS <- c("estabelecimentos", "vinculos_ativos", "vinculos_com_remuneracao", "massa_salarial_dez")
REGIOES_RAIS <- list(
  CENTRO_OESTE = c("MS", "MT", "GO", "DF"),
  MG_ES_RJ = c("MG", "ES", "RJ"),
  NORDESTE = c("MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA"),
  NORTE = c("RO", "AC", "AM", "RR", "PA", "AP", "TO"),
  SP = "SP",
  SUL = c("PR", "SC", "RS")
)

dir_bruto <- dir_brutos(FONTE)
dir_parciais <- dir_brutos(FONTE, "parciais")
dicionario <- carregar_dicionario_municipios()   # ja restrito as UFs ativas (PAINEL_UFS)
ufs <- UFS_ATIVAS$uf
# As parciais dependem do recorte de UFs: um recorte de teste nao pode ser
# confundido com a rodada nacional.
sufixo_ufs <- if (nrow(UFS_ATIVAS) < nrow(UFS)) paste0("_", paste(sort(ufs), collapse = "_")) else ""

# ---- 1. Ferramentas: 7-Zip e leitura em fluxo -------------------------------
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
EXE_7Z <- localizar_7zip()
log_msg("7-Zip: ", EXE_7Z)

abrir_fluxo <- function(arquivo) {
  # Conexao binaria com o conteudo descompactado, sem gravar nada em disco:
  # .7z via "7z x -so" (stdout) e .zip (estabelecimentos de 2002) via unz().
  # No Windows os caminhos curtos (8.3) evitam espacos e acentos na linha de
  # comando; aspas so quando ainda restar espaco.
  if (grepl("[.]zip$", arquivo, ignore.case = TRUE)) {
    return(unz(arquivo, listar_membros_zip(arquivo)[[1L]], open = "rb"))
  }
  windows <- .Platform$OS.type == "windows"
  preparar <- function(x) {
    if (windows) x <- utils::shortPathName(normalizePath(x, winslash = "\\", mustWork = TRUE))
    if (grepl("[[:space:]]", x)) shQuote(x, type = if (windows) "cmd" else "sh") else x
  }
  pipe(paste(preparar(EXE_7Z), "x -so", preparar(arquivo)), open = "rb")
}

encontrar_coluna <- function(nomes, padroes, rotulo, obrigatoria = TRUE) {
  # Casa o cabecalho normalizado (sem acento, minusculas, sem pontuacao) com
  # padroes que cobrem os layouts antigos ("Municipio") e os recentes
  # ("Municipio - Codigo"). Exige correspondencia unica.
  chave <- normalizar_nome(nomes)
  for (padrao in padroes) {
    posicao <- grep(padrao, chave)
    if (length(posicao) == 1L) return(nomes[posicao])
  }
  if (!obrigatoria) return(NA_character_)
  stop("Coluna nao identificada para ", rotulo, ". Cabecalho: ", paste(nomes, collapse = " | "))
}

num <- function(x) if (is.numeric(x)) as.numeric(x) else para_numero(x)

setor_subsetor <- function(x) {
  # Agrupamento do IBGE Subsetor (codigos 1 a 25) usado nas tabulacoes da RAIS.
  z <- suppressWarnings(as.integer(num(x)))
  fcase(z >= 1L & z <= 14L, "industria",
        z == 15L, "construcao_civil",
        z %in% 16:17, "comercio",
        z %in% 18:24, "servicos",
        z == 25L, "agropecuaria",
        default = "nao_classificado")
}

processar_arquivo <- function(arquivo, tipo) {
  # Le o arquivo em blocos direto do fluxo descompactado, mantem so as colunas
  # necessarias e acumula contagens/somas por municipio (6 digitos) e setor.
  # Separador ";" e decimal ","; os bytes chegam em Latin-1 (ou UTF-8, detectado
  # pelo cabecalho) e sao convertidos para UTF-8 antes do fread.
  con <- abrir_fluxo(arquivo)
  aberta <- TRUE
  on.exit(if (aberta) try(close(con), silent = TRUE), add = TRUE)
  primeira <- readLines(con, n = 1L, warn = FALSE, encoding = "bytes")
  if (!length(primeira) || !nzchar(primeira)) stop("Conteudo vazio em ", basename(arquivo))
  codificacao <- if (is.na(iconv(primeira, from = "UTF-8", to = "UTF-8"))) "latin1" else "UTF-8"
  converter <- function(x) iconv(x, from = codificacao, to = "UTF-8", sub = "")
  cabecalho <- sub("^\ufeff", "", converter(primeira))
  nomes <- names(fread(text = cabecalho, sep = ";", header = TRUE, nrows = 0L, encoding = "UTF-8", check.names = FALSE))

  # Municipio do estabelecimento (o arquivo de vinculos tambem traz o municipio
  # de trabalho, "Mun Trab", que nao e usado).
  col_mun <- encontrar_coluna(nomes, "^municipio( codigo)?$", "municipio do estabelecimento")
  col_sub <- encontrar_coluna(nomes, "^ibge subsetor( codigo)?$", "subsetor IBGE")
  if (tipo == "estab") {
    col_ativo <- encontrar_coluna(nomes, "^ind atividade ano( codigo)?$", "atividade no ano")
    col_excluir <- encontrar_coluna(nomes, "^ind rais negativa( codigo)?$", "RAIS negativa")
    col_remun <- NA_character_
  } else {
    col_ativo <- encontrar_coluna(nomes, "^vinculo ativo 31 12( codigo)?$", "vinculo ativo em 31/12")
    col_remun <- encontrar_coluna(nomes, c("^vl remun dezembro nom$", "^vl rem dezembro nom$", "remun.*dezembro.*nom"),
                                  "remuneracao nominal de dezembro")
    # Marca de vinculo abandonado: existe so nos layouts recentes; quando
    # ausente, nenhum vinculo e excluido por esse criterio.
    col_excluir <- encontrar_coluna(nomes, c("^vinculo abandonado( codigo)?$", "vinculo abandonado"),
                                    "vinculo abandonado", obrigatoria = FALSE)
  }
  selecionar <- c(codigo6 = col_mun, subsetor = col_sub, ativo = col_ativo, remuneracao = col_remun, excluir = col_excluir)
  selecionar <- selecionar[!is.na(selecionar)]

  acumulado <- NULL
  lidas <- 0
  blocos <- 0L
  repeat {
    linhas <- converter(readLines(con, n = TAMANHO_BLOCO, warn = FALSE, encoding = "bytes"))
    if (!length(linhas)) break
    linhas <- linhas[linhas != cabecalho]   # arquivos com mais de um membro repetem o cabecalho
    lidas <- lidas + length(linhas)
    blocos <- blocos + 1L
    if (!length(linhas)) next
    dt <- fread(text = paste(c(cabecalho, linhas), collapse = "\n"), sep = ";", dec = ",", header = TRUE,
                select = unname(selecionar), encoding = "UTF-8", showProgress = FALSE, check.names = FALSE)
    setnames(dt, unname(selecionar), names(selecionar))
    dt[, codigo6 := sprintf("%06d", as.integer(num(codigo6)))]
    dt <- dt[codigo6 %in% dicionario$codigo6 & as.integer(num(ativo)) == 1L]
    if ("excluir" %in% names(dt)) dt <- dt[as.integer(num(excluir)) == 0L]
    if (nrow(dt)) {
      dt[, setor := setor_subsetor(subsetor)]
      parte <- if (tipo == "estab") {
        dt[, .(estabelecimentos = .N), by = .(codigo6, setor)]
      } else {
        dt[, remuneracao := num(remuneracao)]
        dt[, .(vinculos_ativos = .N,
               vinculos_com_remuneracao = sum(!is.na(remuneracao)),
               massa_salarial_dez = sum(remuneracao, na.rm = TRUE)), by = .(codigo6, setor)]
      }
      acumulado <- rbindlist(list(acumulado, parte))[, lapply(.SD, sum), by = .(codigo6, setor)]
    }
    if (blocos %% 10L == 0L) log_msg("  ", basename(arquivo), ": ", format(lidas, big.mark = "."), " linhas lidas")
  }
  status <- close(con)
  aberta <- FALSE
  if (inherits(con, "pipe") && is.numeric(status) && status != 0) {
    stop("O 7-Zip terminou com erro ", status, " ao ler ", basename(arquivo), ": arquivo corrompido ou incompleto.")
  }
  if (is.null(acumulado)) {
    stop("Nenhum registro de municipio do dicionario em ", basename(arquivo), " apos ",
         format(lidas, big.mark = "."), " linhas: confira as colunas do layout.")
  }
  log_msg("  ", basename(arquivo), ": ", format(lidas, big.mark = "."), " linhas; ",
          uniqueN(acumulado$codigo6), " municipios")
  acumulado
}

# ---- 2. Um ano por vez, com parcial para retomada ---------------------------
identificar_arquivo <- function(arquivo, ano) {
  # Tipo (estab/vinc) e UFs cobertas; NULL para arquivos ignorados (NI etc.).
  nome <- toupper(basename(arquivo))
  if (nome == "RAIS_ESTAB_PUB.7Z" || grepl(paste0("^ESTB", ano, "[.](7Z|ZIP)$"), nome)) {
    return(list(tipo = "estab", ufs = UFS$uf))
  }
  regiao <- sub("^RAIS_VINC_PUB_(.+)[.]7Z$", "\\1", nome)
  if (regiao %in% names(REGIOES_RAIS)) return(list(tipo = "vinc", ufs = REGIOES_RAIS[[regiao]]))
  if (grepl(paste0("^[A-Z]{2}", ano, "[.]7Z$"), nome) && substr(nome, 1L, 2L) %in% UFS$uf) {
    return(list(tipo = "vinc", ufs = substr(nome, 1L, 2L)))
  }
  NULL
}

processar_ano <- function(ano) {
  parcial <- file.path(dir_parciais, paste0("rais_", ano, sufixo_ufs, ".csv"))
  if (file.exists(parcial) && !REPROCESSAR) {
    log_msg("Ano ", ano, ": parcial reutilizada (", basename(parcial), ")")
    return(as.data.table(ler_csv(parcial, colunas_texto = "codigo6")))
  }
  arquivos <- list.files(file.path(dir_bruto, ano), pattern = "[.](7z|zip)$", full.names = TRUE, ignore.case = TRUE)
  plano <- rbindlist(lapply(arquivos, function(a) {
    info <- identificar_arquivo(a, ano)
    if (is.null(info) || !any(info$ufs %in% ufs)) return(NULL)
    data.table(arquivo = a, tipo = info$tipo)
  }))
  if (!nrow(plano) || !all(c("estab", "vinc") %in% plano$tipo)) {
    log_msg("Aviso: ano ", ano, " sem arquivos de estabelecimentos e de vinculos para as UFs ativas; ignorado.")
    return(NULL)
  }
  log_msg("Ano ", ano, ": ", nrow(plano), " arquivos")
  partes <- lapply(seq_len(nrow(plano)), function(i) processar_arquivo(plano$arquivo[i], plano$tipo[i]))
  somar <- function(lista) rbindlist(lista)[, lapply(.SD, sum), by = .(codigo6, setor)]
  agregado <- merge(somar(partes[plano$tipo == "estab"]), somar(partes[plano$tipo == "vinc"]),
                    by = c("codigo6", "setor"), all = TRUE)
  set(agregado, j = "ano", value = as.integer(ano))
  escrever_csv(agregado, parcial)
  agregado
}

anos <- suppressWarnings(as.integer(basename(list.dirs(dir_bruto, recursive = FALSE))))
anos <- sort(anos[!is.na(anos) & anos >= ANO_INICIAL])
if (!length(anos)) stop("Nenhuma pasta de ano em ", dir_bruto, ". Execute o script 01 antes.")
longo <- rbindlist(lapply(anos, processar_ano), use.names = TRUE, fill = TRUE)
if (!nrow(longo)) stop("Nenhum ano processado.")
cobertura <- longo[, .(municipios = uniqueN(codigo6)), by = ano]
log_msg("Municipios por ano: ", paste(cobertura$ano, cobertura$municipios, sep = "=", collapse = " "))

# ---- 3. Formato largo: totais e aberturas por setor -------------------------
longo[, setor := factor(setor, levels = SETORES)]
largo <- dcast(longo, codigo6 + ano ~ setor, value.var = MEDIDAS)
for (medida in MEDIDAS) {
  colunas <- paste0(medida, "_", SETORES)
  for (col in colunas) if (!col %in% names(largo)) largo[, (col) := NA_real_]
  # Municipio presente no arquivo do ano: setor sem registro e zero real.
  # Municipio ausente do arquivo: NA (a fonte nao informa).
  presente <- rowSums(!is.na(largo[, colunas, with = FALSE])) > 0L
  for (col in colunas) largo[presente & is.na(get(col)), (col) := 0]
  largo[, (medida) := rowSums(.SD), .SDcols = colunas]
}
for (sufixo in c("", paste0("_", SETORES))) {
  largo[, (paste0("remuneracao_media_dez", sufixo)) := fifelse(
    get(paste0("vinculos_com_remuneracao", sufixo)) > 0,
    get(paste0("massa_salarial_dez", sufixo)) / get(paste0("vinculos_com_remuneracao", sufixo)),
    NA_real_)]
}
largo[, codigo_municipio := codigo6_para_7(codigo6, dicionario)]
largo[, codigo6 := NULL]
base <- as.data.table(juntar_dicionario(largo, dicionario))

# ---- 4. Taxa de ocupacao (populacao residente estimada, Ipeadata/IBGE) ------
base[, taxa_ocupacao := NA_real_]
pop <- tryCatch(as.data.table(ipeadata_municipal("ESTIMA_PO")), error = function(e) {
  log_msg("Aviso: populacao do Ipeadata indisponivel (", conditionMessage(e), "); taxa_ocupacao ficara vazia.")
  NULL
})
if (!is.null(pop)) {
  pop <- unique(pop[!is.na(codigo_municipio) & !is.na(valor), .(codigo_municipio, ano, populacao = valor)],
                by = c("codigo_municipio", "ano"))
  base[pop, on = .(codigo_municipio, ano),
       taxa_ocupacao := fifelse(i.populacao > 0, vinculos_ativos / i.populacao, NA_real_)]
  log_msg("Taxa de ocupacao calculada para ", sum(!is.na(base$taxa_ocupacao)), " de ", nrow(base), " municipio-anos.")
}

# ---- 5. Opcional: valores em reais de um ano-base (deflator IPCA) -----------
if (!is.na(ANO_BASE_REAIS)) {
  fatores <- as.data.table(deflator_ipca_anual(ANO_BASE_REAIS))[, .(ano, fator)]
  base[fatores, on = "ano", `:=`(massa_reais = massa_salarial_dez * i.fator,
                                 remun_reais = remuneracao_media_dez * i.fator)]
  setnames(base, c("massa_reais", "remun_reais"),
           paste0(c("massa_salarial_dez_reais_", "remuneracao_media_dez_reais_"), ANO_BASE_REAIS))
}

# ---- 6. Gravacao da base e do dicionario de variaveis -----------------------
ordem <- c(CHAVES_MUNICIPAIS, "estabelecimentos", "vinculos_ativos", "vinculos_com_remuneracao",
           "massa_salarial_dez", "remuneracao_media_dez", "taxa_ocupacao",
           paste0("estabelecimentos_", SETORES), paste0("vinculos_ativos_", SETORES),
           paste0("vinculos_com_remuneracao_", SETORES), paste0("massa_salarial_dez_", SETORES),
           paste0("remuneracao_media_dez_", SETORES))
setcolorder(base, c(ordem, setdiff(names(base), ordem)))
salvar_base_tratada(FONTE, base)

rotulo_setor <- c(industria = "industria (IBGE subsetor 1 a 14)", construcao_civil = "construcao civil (15)",
                  comercio = "comercio (16 e 17)", servicos = "servicos (18 a 24)",
                  agropecuaria = "agropecuaria (25)", nao_classificado = "nao classificado ou ignorado")
descricoes <- c(
  estabelecimentos = "Estabelecimentos com atividade no ano e declaracao positiva (Ind Atividade Ano = 1 e Ind RAIS Negativa = 0)",
  vinculos_ativos = "Vinculos empregaticios ativos em 31/12 (excluidos os marcados como abandonados nos layouts que trazem a marca)",
  vinculos_com_remuneracao = "Vinculos ativos em 31/12 com remuneracao de dezembro informada (denominador da remuneracao media)",
  massa_salarial_dez = "Soma da remuneracao nominal de dezembro dos vinculos ativos em 31/12",
  remuneracao_media_dez = "Massa salarial de dezembro dividida pelos vinculos com remuneracao de dezembro informada",
  taxa_ocupacao = "Vinculos ativos em 31/12 divididos pela populacao residente estimada (Ipeadata ESTIMA_PO, IBGE)"
)
unidades <- c(estabelecimentos = "estabelecimentos", vinculos_ativos = "vinculos", vinculos_com_remuneracao = "vinculos",
              massa_salarial_dez = "R$ correntes", remuneracao_media_dez = "R$ correntes",
              taxa_ocupacao = "razao (vinculos por habitante)")
dic_var <- rbindlist(lapply(names(descricoes), function(v) {
  linhas <- data.table(variavel = v, descricao = descricoes[[v]], unidade = unidades[[v]])
  if (v == "taxa_ocupacao") return(linhas)
  rbind(linhas, data.table(variavel = paste0(v, "_", SETORES),
                           descricao = paste0(descricoes[[v]], " - ", rotulo_setor[SETORES]),
                           unidade = unidades[[v]]))
}))
if (!is.na(ANO_BASE_REAIS)) {
  dic_var <- rbind(dic_var, data.table(
    variavel = paste0(c("massa_salarial_dez", "remuneracao_media_dez"), "_reais_", ANO_BASE_REAIS),
    descricao = paste0(c("Massa salarial de dezembro", "Remuneracao media de dezembro"), " em reais de ",
                       ANO_BASE_REAIS, " (deflator IPCA medio anual, SGS 433)"),
    unidade = paste0("R$ de ", ANO_BASE_REAIS)))
}
dic_var[, `:=`(periodicidade = "anual", fonte_url = URL_FONTE)]
salvar_dicionario_variaveis(FONTE, dic_var)
