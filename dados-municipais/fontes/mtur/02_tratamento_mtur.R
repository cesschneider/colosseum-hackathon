# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_mtur.R
# FONTE: Ministerio do Turismo - Cadastur / Dados Abertos (meios de hospedagem
#        e guias de turismo)
# OBJETIVO: Ler os retratos anuais do cadastro (CSV/XLS/XLSX com layouts que
#           mudam ao longo do tempo), casar municipio por nome + UF com o
#           dicionario IBGE e contar, por municipio-ano, meios de hospedagem,
#           leitos, unidades habitacionais e guias de turismo.
# ENTRADAS: dados/brutos/mtur/mtur_<hospedagem|guias>_<ANO>_<periodo>.<ext>
# SAIDAS: dados/tratados/mtur/mtur_municipal.csv
#         dados/tratados/mtur/mtur_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/mtur/02_tratamento_mtur.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table", "readxl"))
library(data.table)
FONTE <- "mtur"

INDICADORES <- c("n_meios_hospedagem", "n_leitos", "n_unidades_habitacionais", "n_guias_turismo")
# fill = Inf (data.table >= 1.16) aceita linhas com campos a mais, comuns nos
# CSVs historicos; versoes antigas so aceitam TRUE e podem truncar a leitura.
FILL_FREAD <- if (utils::packageVersion("data.table") >= "1.16.0") Inf else TRUE

dicionario <- carregar_dicionario_municipios()
arquivos <- list.files(dir_brutos(FONTE),
                       pattern = "^mtur_(hospedagem|guias)_[0-9]{4}_(anual|t[1-4])[.](csv|xls|xlsx)$",
                       full.names = TRUE)
if (!length(arquivos)) stop("Nenhum bruto encontrado. Execute o script 01 antes.")

# Um retrato por tipo-ano; se restar mais de um, fica o periodo mais recente.
partes <- regmatches(basename(arquivos),
                     regexec("^mtur_(hospedagem|guias)_([0-9]{4})_(anual|t[1-4])[.](csv|xls|xlsx)$", basename(arquivos)))
info <- rbindlist(lapply(partes, function(p) data.table(tipo = p[2], ano = as.integer(p[3]),
                                                        periodo = p[4], extensao = p[5])))
info[, arquivo := arquivos]
info[, ordem := ifelse(periodo == "anual", 5L, as.integer(substr(periodo, 2L, 2L)))]
setorder(info, tipo, ano, -ordem)
info <- info[!duplicated(info[, .(tipo, ano)])]

# ---- Leitura tolerante aos layouts da fonte -----------------------------------

nome_coluna <- function(x) {
  # "Numero de Inscricao do CNPJ" -> "numero_de_inscricao_do_cnpj"
  x <- gsub(" ", "_", normalizar_nome(x))
  x[is.na(x) | !nzchar(x)] <- "coluna"
  make.unique(x, sep = "_")
}

ler_csv_mtur <- function(arquivo) {
  # CSVs historicos: Windows-1252/Latin-1 (alguns UTF-8), linhas terminadas em
  # CRLF, LF ou apenas CR, campos ora entre aspas ora nao, aspas avulsas e
  # linhas com campos a mais. O texto e normalizado antes do fread.
  texto <- rawToChar(readBin(arquivo, "raw", n = file.info(arquivo)$size))
  if (validUTF8(texto)) {
    Encoding(texto) <- "UTF-8"
  } else {
    Encoding(texto) <- "latin1"
    texto <- iconv(texto, "latin1", "UTF-8", sub = "")
  }
  texto <- sub("^\ufeff", "", gsub("\r\n?", "\n", texto))
  ler <- function(aspas) fread(text = texto, sep = ";", header = TRUE, fill = FILL_FREAD,
                               quote = aspas, colClasses = "character", encoding = "UTF-8",
                               na.strings = c("", "NA"), blank.lines.skip = TRUE)
  dados <- ler("\"")
  # Aspas avulsas no corpo podem fazer o fread devolver o cabecalho em uma so coluna.
  if (ncol(dados) == 1L && grepl(";", names(dados)[1L], fixed = TRUE)) dados <- ler("")
  n_linhas <- length(gregexpr("\n", texto, fixed = TRUE)[[1L]])
  if (nrow(dados) < 0.9 * (n_linhas - 1L)) {
    stop("Leitura truncada de ", basename(arquivo), " (", nrow(dados), " de ~", n_linhas,
         " linhas). Atualize o data.table para 1.16 ou superior.")
  }
  dados
}

ler_excel_mtur <- function(arquivo, tipo) {
  abas <- readxl::excel_sheets(arquivo)
  if (tipo == "guias" && length(abas) > 1L) {
    # Desde 2024 os guias vem em abas separadas (pessoa fisica e juridica);
    # as duas precisam entrar, senao metade dos guias desaparece.
    abas <- abas[grepl("guia", normalizar_nome(abas))]
    chaves <- normalizar_nome(abas)
    if (!any(grepl("\\bpf\\b", chaves)) || !any(grepl("\\bpj\\b", chaves))) {
      stop("Abas PF/PJ de guias nao identificadas em ", basename(arquivo), ": ", paste(abas, collapse = " | "))
    }
  }
  rbindlist(lapply(abas, function(aba) {
    x <- as.data.table(readxl::read_excel(arquivo, sheet = aba, col_types = "text", .name_repair = "minimal"))
    setnames(x, nome_coluna(names(x)))
    x
  }), use.names = TRUE, fill = TRUE)
}

localizar <- function(dados, alternativas, descricao, arquivo) {
  # Primeira coluna encontrada na ordem de preferencia (nomes mudam entre anos).
  achada <- intersect(alternativas, names(dados))
  if (!length(achada)) {
    stop("Coluna de ", descricao, " nao encontrada em ", basename(arquivo), ". Colunas: ",
         paste(names(dados), collapse = " | "))
  }
  dados[[achada[1L]]]
}

processar_arquivo <- function(i) {
  arquivo <- info$arquivo[i]
  tipo <- info$tipo[i]
  dados <- if (info$extensao[i] == "csv") ler_csv_mtur(arquivo) else ler_excel_mtur(arquivo, tipo)
  setnames(dados, nome_coluna(names(dados)))
  saida <- data.table(
    tipo = tipo, ano = info$ano[i],
    uf = toupper(trimws(localizar(dados, "uf", "UF", arquivo))),
    municipio = trimws(localizar(dados, c("municipio", "localidade"), "municipio", arquivo))
  )
  if (tipo == "hospedagem") {
    # Estabelecimento = CNPJ distinto; leitos e UH somados sobre as linhas.
    saida[, `:=`(
      identificador = gsub("[^0-9]", "", localizar(dados, c("cnpj", "numero_de_inscricao_do_cnpj"), "CNPJ", arquivo)),
      unidades_habitacionais = para_numero(localizar(dados, c("uh", "unidade_habitacionais", "unidades_habitacionais"),
                                                     "unidades habitacionais", arquivo)),
      leitos = para_numero(localizar(dados, c("total_de_leitos", "leitos"), "leitos", arquivo))
    )]
  } else {
    # Identificador do guia: CPF, depois certificado, CNPJ e nome (os arquivos
    # antigos so trazem o nome). CPF/CNPJ ficam so com digitos, o que permite
    # casar o mesmo guia entre as abas PF e PJ.
    candidatas <- intersect(c("cpf", "numero_do_certificado", "numero_de_inscricao_do_cnpj", "cnpj",
                              "nome_completo", "nome_do_responsavel", "nome_do_prestador", "nome"), names(dados))
    if (!length(candidatas)) stop("Identificador do guia nao encontrado em ", basename(arquivo))
    identificador <- rep(NA_character_, nrow(dados))
    for (coluna in candidatas) {
      valor <- trimws(dados[[coluna]])
      valor[valor %in% c("", "-", "NA")] <- NA_character_
      usar <- is.na(identificador) & !is.na(valor)
      identificador[usar] <- valor[usar]
    }
    digitos <- gsub("[^0-9]", "", identificador)
    numerico <- !is.na(identificador) & nchar(digitos) %in% c(11L, 14L)
    identificador[numerico] <- digitos[numerico]
    textual <- !numerico & !is.na(identificador)
    identificador[textual] <- normalizar_nome(identificador[textual])
    saida[, identificador := identificador]
  }
  log_msg(basename(arquivo), ": ", nrow(saida), " registros")
  saida
}

# ---- Empilhamento, casamento municipal e contagens ---------------------------

registros <- rbindlist(lapply(seq_len(nrow(info)), processar_arquivo), fill = TRUE)
registros <- registros[!is.na(municipio) & nzchar(municipio)]          # linhas vazias/rodape
registros[is.na(identificador) | !nzchar(identificador), identificador := paste0("sem_id_", .I)]

# O Cadastur nao traz o codigo IBGE: casamento por nome normalizado + UF.
# Nomes sem correspondencia (grafias divergentes) ficam fora da base.
registros <- as.data.table(juntar_por_nome_uf(registros, "municipio", "uf", dicionario))
registros <- registros[!is.na(codigo_municipio)]

hospedagem <- registros[tipo == "hospedagem", .(
  n_meios_hospedagem = uniqueN(identificador),
  n_leitos = sum(leitos, na.rm = TRUE),
  n_unidades_habitacionais = sum(unidades_habitacionais, na.rm = TRUE)
), by = .(codigo_municipio, ano)]
guias <- registros[tipo == "guias", .(n_guias_turismo = uniqueN(identificador)), by = .(codigo_municipio, ano)]

# Cada ano precisa dos dois retratos; sem um deles, o zero abaixo seria falso.
anos_incompletos <- setdiff(union(hospedagem$ano, guias$ano), intersect(hospedagem$ano, guias$ano))
if (length(anos_incompletos)) stop("Anos sem hospedagem ou sem guias: ", paste(sort(anos_incompletos), collapse = ", "))

# Municipio presente em um cadastro e ausente no outro: zero registros (o
# cadastro e exaustivo), nao dado faltante.
base <- merge(hospedagem, guias, by = c("codigo_municipio", "ano"), all = TRUE)
setnafill(base, type = "const", fill = 0, cols = INDICADORES)
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base)

salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = INDICADORES,
  descricao = c(
    "Numero de meios de hospedagem cadastrados no Cadastur (CNPJ distintos) no retrato do ano",
    "Numero de leitos dos meios de hospedagem cadastrados (soma) no retrato do ano",
    "Numero de unidades habitacionais dos meios de hospedagem cadastrados (soma) no retrato do ano",
    "Numero de guias de turismo cadastrados no Cadastur (pessoas distintas) no retrato do ano"
  ),
  unidade = c("estabelecimentos", "leitos", "unidades habitacionais", "guias"),
  periodicidade = "anual",
  fonte_url = "https://dados.turismo.gov.br/",
  stringsAsFactors = FALSE
))
