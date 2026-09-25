# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_bcb_estban.R
# FONTE: Banco Central do Brasil - ESTBAN (Estatistica Bancaria Mensal por
#        Municipio, documento 4500)
# OBJETIVO: Ler os arquivos mensais brutos, somar os saldos das agencias de
#           cada municipio e gravar a base municipal mensal (valores nominais
#           em R$ correntes) com o dicionario de variaveis.
# ENTRADAS: dados/brutos/bcb_estban/AAAAMM_ESTBAN.<ZIP|csv|csv.zip>
# SAIDAS: dados/tratados/bcb_estban/bcb_estban_municipal.csv
#         dados/tratados/bcb_estban/bcb_estban_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/bcb_estban/02_tratamento_bcb_estban.R
#   Para testes: PAINEL_ANO_INICIAL=2023 (processa so os meses desse ano em diante)
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table"))
library(data.table)
FONTE <- "bcb_estban"

ANO_INICIAL <- ano_inicial_efetivo(2000L)
dicionario <- carregar_dicionario_municipios()

# 1. Inventario dos brutos: um arquivo por mes (se houver dois formatos para
#    o mesmo mes, fica o mais recente).
arquivos <- list.files(dir_brutos(FONTE), pattern = "^[0-9]{6}_ESTBAN([.]csv)?([.]zip)?$",
                       full.names = TRUE, ignore.case = TRUE)
if (!length(arquivos)) stop("Nenhum bruto encontrado. Execute o script 01 antes.")
inventario <- data.table(arquivo = arquivos, periodo = substr(basename(arquivos), 1L, 6L),
                         modificado = file.mtime(arquivos))
inventario <- inventario[as.integer(substr(periodo, 1L, 4L)) >= ANO_INICIAL]
setorder(inventario, periodo, -modificado)
if (anyDuplicated(inventario$periodo)) log_msg("Aviso: mais de um arquivo para o mesmo mes; usando o mais recente.")
inventario <- inventario[!duplicated(periodo)]
log_msg(nrow(inventario), " meses a processar (", min(inventario$periodo), " a ", max(inventario$periodo), ").")

# 2. Layout do ESTBAN: 2 linhas de titulo, cabecalho na 3a linha, separador ";",
#    Latin-1, valores inteiros em R$. Os nomes dos verbetes mudam ao longo do
#    tempo (ex.: "VERBETE_167_...+VERBETE_168_..."), por isso a busca e pelo
#    prefixo "VERBETE_<codigo>". A coluna de depositos a vista e a agregada
#    401+...+419; os verbetes rurais 164-166 deixaram de ser publicados
#    separadamente (163 e 167 sao obrigatorios e a soma usa os existentes).
localizar_verbete <- function(cabecalho, codigo, obrigatorio = TRUE) {
  achados <- cabecalho[grepl(paste0("^VERBETE_", codigo, "(_|[ +])"), cabecalho, perl = TRUE)]
  if (length(achados) > 1L) stop("Mais de uma coluna para o verbete ", codigo, ".")
  if (!length(achados)) {
    if (obrigatorio) stop("Verbete obrigatorio ausente: ", codigo, ".")
    return(NA_character_)
  }
  achados
}

mapear_colunas <- function(cabecalho, periodo) {
  exata <- function(nome) {
    if (!nome %in% cabecalho) stop("Coluna ", nome, " ausente em ", periodo, ".")
    nome
  }
  vista <- localizar_verbete(cabecalho, 401L)
  if (!grepl("VERBETE_419", vista, fixed = TRUE)) {
    stop("A coluna de depositos a vista (401) nao agrega ate o verbete 419 em ", periodo, ".")
  }
  rurais <- vapply(163:167, function(z) localizar_verbete(cabecalho, z, obrigatorio = FALSE), character(1L))
  names(rurais) <- paste0("rural_", 163:167)
  if (is.na(rurais[["rural_163"]]) || is.na(rurais[["rural_167"]])) {
    stop("Verbetes rurais 163 e 167 sao obrigatorios e nao foram encontrados em ", periodo, ".")
  }
  c(uf = exata("UF"), codigo = exata("CODMUN_IBGE"), agencias = exata("AGEN_PROCESSADAS"),
    credito = localizar_verbete(cabecalho, 160L), emprestimos = localizar_verbete(cabecalho, 161L),
    imobiliario = localizar_verbete(cabecalho, 169L), vista = vista,
    poupanca = localizar_verbete(cabecalho, 420L), interfin_430 = localizar_verbete(cabecalho, 430L),
    interfin_431 = localizar_verbete(cabecalho, 431L), prazo = localizar_verbete(cabecalho, 432L),
    rurais[!is.na(rurais)])
}

soma_linha <- function(dt) {
  # Soma por linha preservando NA quando todos os componentes sao NA.
  m <- as.matrix(dt)
  s <- rowSums(m, na.rm = TRUE)
  s[rowSums(!is.na(m)) == 0L] <- NA_real_
  s
}
soma_na <- function(v) if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE)

tratar_mes <- function(arquivo, periodo) {
  csv <- arquivo
  if (grepl("[.]zip$", arquivo, ignore.case = TRUE)) {
    pasta_tmp <- tempfile("estban_")
    on.exit(unlink(pasta_tmp, recursive = TRUE, force = TRUE), add = TRUE)
    membro <- grep("[.]csv$", listar_membros_zip(arquivo), ignore.case = TRUE, value = TRUE)
    if (length(membro) != 1L) stop("Esperado um unico CSV dentro de ", basename(arquivo), ".")
    descompactar_zip(arquivo, pasta_tmp, membros = membro)
    csv <- file.path(pasta_tmp, membro)
  }
  cabecalho <- names(fread(csv, sep = ";", skip = 2L, nrows = 0L, encoding = "Latin-1", check.names = FALSE))
  mapa <- mapear_colunas(cabecalho, periodo)
  x <- fread(csv, sep = ";", skip = 2L, select = unname(mapa), colClasses = "character",
             encoding = "Latin-1", check.names = FALSE, na.strings = c("", "NA"), showProgress = FALSE)
  setnames(x, unname(mapa), names(mapa))
  # Linhas sem codigo IBGE sao registros tecnicos da fonte (0 agencias), nao municipios.
  x[, codigo := gsub("[^0-9]", "", codigo)]
  x <- x[!is.na(codigo) & nzchar(codigo)]
  x[nchar(codigo) == 6L, codigo := codigo6_para_7(codigo, dicionario)]
  x[, codigo := padronizar_codigo7(codigo)]
  x <- x[!is.na(codigo)]
  numericas <- setdiff(names(x), c("uf", "codigo"))
  x[, (numericas) := lapply(.SD, para_numero), .SDcols = numericas]
  x[, rural := soma_linha(.SD), .SDcols = grep("^rural_", names(x), value = TRUE)]
  x[, depositos := soma_linha(.SD), .SDcols = c("vista", "poupanca", "interfin_430", "interfin_431", "prazo")]
  saida <- x[, .(
    numero_agencias = soma_na(agencias),
    operacoes_credito = soma_na(credito),
    emprestimos_titulos_descontados = soma_na(emprestimos),
    credito_rural = soma_na(rural),
    credito_imobiliario = soma_na(imobiliario),
    depositos_vista = soma_na(vista),
    depositos_poupanca = soma_na(poupanca),
    depositos_prazo = soma_na(prazo),
    depositos_total = soma_na(depositos)
  ), by = .(codigo_municipio = codigo)]
  saida[, `:=`(ano = as.integer(substr(periodo, 1L, 4L)), mes = as.integer(substr(periodo, 5L, 6L)))]
  saida
}

# 3. Processamento mes a mes (soma das agencias de cada municipio)
bases <- vector("list", nrow(inventario))
for (i in seq_len(nrow(inventario))) {
  periodo <- inventario$periodo[i]
  if (substr(periodo, 5L, 6L) == "01" || i == 1L) log_msg("Processando ", substr(periodo, 1L, 4L), "...")
  bases[[i]] <- tratar_mes(inventario$arquivo[i], periodo)
}
base <- rbindlist(bases, use.names = TRUE)
setorder(base, codigo_municipio, ano, mes)
if (anyDuplicated(base, by = c("codigo_municipio", "ano", "mes"))) stop("Chave municipio-mes duplicada apos a agregacao.")

# 4. Variacao mensal dos estoques de depositos (primeira diferenca), calculada
#    apenas quando o mes imediatamente anterior existe para o municipio.
base[, indice_mes := ano * 12L + mes]
base[, `:=`(
  variacao_depositos_vista = fifelse(indice_mes - shift(indice_mes) == 1L, depositos_vista - shift(depositos_vista), NA_real_),
  variacao_depositos_poupanca = fifelse(indice_mes - shift(indice_mes) == 1L, depositos_poupanca - shift(depositos_poupanca), NA_real_),
  variacao_depositos_prazo = fifelse(indice_mes - shift(indice_mes) == 1L, depositos_prazo - shift(depositos_prazo), NA_real_)
), by = codigo_municipio]
base[, indice_mes := NULL]

# 5. Nome/UF oficiais e gravacao
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base, mensal = TRUE)

URL_ESTBAN <- "https://www.bcb.gov.br/estatisticas/estatisticabancariamunicipios"
salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = c("numero_agencias", "operacoes_credito", "emprestimos_titulos_descontados", "credito_rural",
               "credito_imobiliario", "depositos_vista", "depositos_poupanca", "depositos_prazo",
               "depositos_total", "variacao_depositos_vista", "variacao_depositos_poupanca",
               "variacao_depositos_prazo"),
  descricao = c(
    "Numero de agencias bancarias com balancete processado no mes (soma de AGEN_PROCESSADAS)",
    "Saldo de operacoes de credito (verbete 160)",
    "Saldo de emprestimos e titulos descontados (verbete 161)",
    "Saldo de financiamentos rurais e agroindustriais (soma dos verbetes 163 a 167 publicados; 163 e 167 sempre presentes)",
    "Saldo de financiamentos imobiliarios (verbete 169)",
    "Saldo de depositos a vista (verbetes 401 a 419)",
    "Saldo de depositos de poupanca (verbete 420)",
    "Saldo de depositos a prazo (verbete 432)",
    "Saldo total de depositos: a vista, poupanca, interfinanceiros (430 e 431) e a prazo",
    "Variacao do saldo de depositos a vista em relacao ao mes anterior",
    "Variacao do saldo de depositos de poupanca em relacao ao mes anterior",
    "Variacao do saldo de depositos a prazo em relacao ao mes anterior"
  ),
  unidade = c("agencias", rep("R$ correntes", 11L)),
  periodicidade = "mensal",
  tabela = "ESTBAN municipio (documento 4500)",
  fonte_url = URL_ESTBAN,
  stringsAsFactors = FALSE
))
