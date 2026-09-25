# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 02_tratamento_senatran.R
# FONTE: SENATRAN / Ministerio dos Transportes - Frota de veiculos (RENAVAM)
# OBJETIVO: Ler as planilhas mensais de frota por municipio (por combustivel e
#           por tipo de veiculo), casar os municipios com o codigo IBGE (a fonte
#           so traz nome e UF) e gravar a base municipal mensal do painel.
# ENTRADAS: dados/brutos/senatran/combustivel_<ano>_<mes>.xlsx|xls
#           dados/brutos/senatran/tipo_<ano>_<mes>.xlsx|xls|csv
# SAIDAS: dados/tratados/senatran/senatran_municipal.csv
#         dados/tratados/senatran/senatran_dicionario_variaveis.csv
# COMO EXECUTAR: Rscript fontes/senatran/02_tratamento_senatran.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table", "readxl"))
library(data.table)
FONTE <- "senatran"

URL_FONTE <- "https://www.gov.br/transportes/pt-br/assuntos/transito/conteudo-Senatran/frota-de-veiculos-<ANO>"
dicionario <- carregar_dicionario_municipios()
MAPA_UF <- setNames(UFS$uf, normalizar_nome(UFS$nome_uf))   # "SAO PAULO" -> "SP"

# Colunas da planilha "Frota por municipio e tipo" -> variaveis do painel.
MAPA_TIPO <- c(
  "TOTAL" = "frota_total", "AUTOMOVEL" = "frota_automoveis", "BONDE" = "frota_bondes",
  "CAMINHAO" = "frota_caminhoes", "CAMINHAO TRATOR" = "frota_caminhoes_trator",
  "CAMINHONETE" = "frota_caminhonetes", "CAMIONETA" = "frota_camionetas",
  "CHASSI PLATAF" = "frota_chassis_plataforma", "CICLOMOTOR" = "frota_ciclomotores",
  "MICRO-ONIBUS" = "frota_micro_onibus", "MOTOCICLETA" = "frota_motocicletas",
  "MOTONETA" = "frota_motonetas", "ONIBUS" = "frota_onibus", "QUADRICICLO" = "frota_quadriciclos",
  "REBOQUE" = "frota_reboques", "SEMI-REBOQUE" = "frota_semi_reboques", "SIDE-CAR" = "frota_side_cars",
  "OUTROS" = "frota_outros_tipos", "TRATOR ESTEI" = "frota_tratores_esteira",
  "TRATOR RODAS" = "frota_tratores_rodas", "TRICICLO" = "frota_triciclos", "UTILITARIO" = "frota_utilitarios"
)

classificar_categoria <- function(categoria) {
  # Categorias de combustivel do RENAVAM (maiusculas, sem acento) -> grupo.
  grupo <- rep("combustao", length(categoria))
  grupo[categoria %in% c("ELETRICO", "ELETRICO/FONTE EXTERNA", "ELETRICO/FONTE INTERNA",
                         "CELULA COMBUSTIVEL")] <- "bev"
  grupo[categoria == "HIBRIDO PLUG-IN"] <- "phev"
  grupo[categoria %in% c("HIBRIDO", "GASOLINA/ELETRICO", "GASOLINA/ALCOOL/ELETRICO", "DIESEL/ELETRICO",
                         "ETANOL/ELETRICO", "HIBRIDO/GAS NATURAL VEICULAR")] <- "hev"
  grupo[categoria %in% c("SEM INFORMACAO", "NAO IDENTIFICADO", "NAO SE APLICA",
                         "VIDE/CAMPO/OBSERVACAO")] <- "sem_informacao"
  grupo
}

ler_matriz <- function(arquivo) {
  # Planilha inteira como matriz de texto: primeira aba com mais de 100 linhas
  # (pula abas de glossario e abas vazias). A variante .csv usa fread.
  if (grepl("[.]csv$", arquivo)) {
    return(as.matrix(fread(arquivo, header = FALSE, colClasses = "character", fill = TRUE, encoding = "UTF-8")))
  }
  for (aba in readxl::excel_sheets(arquivo)) {
    m <- suppressMessages(readxl::read_excel(arquivo, sheet = aba, col_names = FALSE, col_types = "text"))
    if (nrow(m) > 100L) return(as.matrix(m))
  }
  NULL
}

ler_combustivel <- function(arquivo) {
  # Layout D: UF (nome por extenso ou sigla), Municipio, Combustivel, Qtd.
  m <- ler_matriz(arquivo)
  if (is.null(m) || ncol(m) < 4L || !any(grepl("combust", m[1L, ], ignore.case = TRUE))) {
    log_msg("Layout nao reconhecido, arquivo ignorado: ", basename(arquivo))
    return(NULL)
  }
  d <- data.table(uf = trimws(m[-1L, 1L]), municipio = trimws(m[-1L, 2L]),
                  categoria = toupper(remover_acentos(trimws(m[-1L, 3L]))), qtd = para_numero(m[-1L, 4L]))
  d <- d[!is.na(qtd) & !is.na(uf)]
  d[, uf := ifelse(nchar(uf) == 2L, toupper(uf), MAPA_UF[normalizar_nome(uf)])]
  d[, grupo := classificar_categoria(categoria)]
  d[, .(frota_total_combustivel = sum(qtd),
        frota_eletricos_bev = sum(qtd[grupo == "bev"]),
        frota_hibridos_phev = sum(qtd[grupo == "phev"]),
        frota_hibridos_hev = sum(qtd[grupo == "hev"]),
        frota_combustao = sum(qtd[grupo == "combustao"]),
        frota_sem_informacao = sum(qtd[grupo == "sem_informacao"]),
        frota_gasolina = sum(qtd[categoria == "GASOLINA"]),
        frota_etanol = sum(qtd[categoria == "ALCOOL"]),
        frota_flex = sum(qtd[categoria %in% c("ALCOOL/GASOLINA", "GASOLINA/ALCOOL")]),
        frota_diesel = sum(qtd[categoria == "DIESEL"]),
        frota_gnv = sum(qtd[grepl("GAS NATURAL|GAS METANO|GAS/NATURAL", categoria)])),
    by = .(uf, municipio)]
}

ler_tipo <- function(arquivo) {
  # Frota por municipio e tipo: titulo, total geral e cabecalho duplicado nas
  # primeiras linhas; dados a partir da ultima linha cujo 1o campo e "UF".
  m <- ler_matriz(arquivo)
  linhas_cab <- if (is.null(m)) integer() else which(toupper(trimws(m[, 1L])) == "UF")
  if (!length(linhas_cab)) {
    log_msg("Layout nao reconhecido, arquivo ignorado: ", basename(arquivo))
    return(NULL)
  }
  inicio <- max(linhas_cab)
  cab <- toupper(remover_acentos(trimws(m[inicio, ])))
  cab[is.na(cab)] <- ""
  dados <- m[-seq_len(inicio), , drop = FALSE]
  d <- data.table(uf = toupper(trimws(dados[, 1L])), municipio = trimws(dados[, 2L]))
  for (rotulo in names(MAPA_TIPO)) {
    j <- match(rotulo, cab)
    set(d, j = MAPA_TIPO[[rotulo]], value = if (is.na(j)) NA_real_ else para_numero(dados[, j]))
  }
  desconhecidas <- setdiff(cab[nzchar(cab)], c("UF", "MUNICIPIO", names(MAPA_TIPO)))
  if (length(desconhecidas)) log_msg("Colunas nao mapeadas em ", basename(arquivo), ": ", paste(desconhecidas, collapse = ", "))
  d[!is.na(uf) & nchar(uf) == 2L & !is.na(frota_total)]
}

casar_municipios <- function(chaves) {
  # chaves: data.table(uf, municipio) unicas -> codigo_municipio.
  # 1) nome normalizado + UF (biblioteca); 2) variantes de grafia dentro da
  # mesma UF: nomes truncados em 30 caracteres (prefixo) e diferencas de ate
  # 1-2 caracteres (ex.: PARATI/Paraty, IGUARACI/Iguaracy), so com candidato
  # unico. Municipios renomeados ou "nao informado" ficam sem codigo.
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

# 1. Inventario dos brutos: um arquivo por conjunto-mes (xlsx > xls > csv).
arquivos <- list.files(dir_brutos(FONTE), pattern = "^(combustivel|tipo)_[0-9]{4}_[0-9]{2}[.](xlsx|xls|csv)$",
                       full.names = TRUE)
if (!length(arquivos)) stop("Nenhum bruto encontrado. Execute o script 01 antes.")
meta <- data.table(arquivo = arquivos)
meta[, c("conjunto", "ano", "mes", "ext") := tstrsplit(sub("[.]([a-z]+)$", "_\\1", basename(arquivo)), "_", fixed = TRUE)]
meta[, `:=`(ano = as.integer(ano), mes = as.integer(mes))]
meta <- meta[ano >= ano_inicial_efetivo(2016L)]
meta <- meta[order(conjunto, ano, mes, match(ext, c("xlsx", "xls", "csv")))]
meta <- meta[!duplicated(meta[, .(conjunto, ano, mes)])]

# 2. Leitura e empilhamento (um arquivo com total nacional implausivel e descartado).
empilhar <- function(cj, leitor, coluna_total) {
  itens <- meta[conjunto == cj]
  rbindlist(lapply(seq_len(nrow(itens)), function(i) {
    log_msg("Lendo ", basename(itens$arquivo[i]))
    d <- leitor(itens$arquivo[i])
    if (is.null(d)) return(NULL)
    if (sum(d[[coluna_total]], na.rm = TRUE) < 5e7) {
      log_msg("Total nacional implausivel (", sum(d[[coluna_total]], na.rm = TRUE), "), arquivo ignorado: ",
              basename(itens$arquivo[i]))
      return(NULL)
    }
    d[, `:=`(ano = itens$ano[i], mes = itens$mes[i])]
  }), use.names = TRUE, fill = TRUE)
}
comb <- empilhar("combustivel", ler_combustivel, "frota_total_combustivel")
tipo <- empilhar("tipo", ler_tipo, "frota_total")
if (!nrow(comb) && !nrow(tipo)) stop("Nenhum bruto pode ser lido.")

# 3. Nome + UF -> codigo IBGE (uma vez, sobre as chaves unicas) e descarte do
#    que nao casou, com log da taxa de descarte.
chaves <- unique(rbindlist(list(if (nrow(comb)) comb[, .(uf, municipio)], if (nrow(tipo)) tipo[, .(uf, municipio)])))
chaves <- casar_municipios(chaves)
juntar_codigo <- function(d, rotulo) {
  if (!nrow(d)) return(d)
  d <- merge(d, chaves[, .(uf, municipio, codigo_municipio)], by = c("uf", "municipio"), all.x = TRUE)
  perdidas <- sum(is.na(d$codigo_municipio))
  log_msg(rotulo, ": ", perdidas, " de ", nrow(d), " linhas descartadas sem codigo IBGE (",
          round(100 * perdidas / nrow(d), 2), "%)")
  d <- d[!is.na(codigo_municipio)][, c("uf", "municipio") := NULL]
  d[, lapply(.SD, sum), by = .(codigo_municipio, ano, mes)]   # grafias distintas do mesmo municipio
}
comb <- juntar_codigo(comb, "combustivel")
tipo <- juntar_codigo(tipo, "tipo")

# 4. Base municipal mensal: juncao externa dos dois conjuntos e gravacao.
chave <- c("codigo_municipio", "ano", "mes")
base <- if (nrow(comb) && nrow(tipo)) merge(comb, tipo, by = chave, all = TRUE) else if (nrow(comb)) comb else tipo
base <- juntar_dicionario(base, dicionario)
salvar_base_tratada(FONTE, base, mensal = TRUE)

descricoes <- c(
  frota_total = "Frota de veiculos com placa registrados no RENAVAM (planilha por tipo)",
  frota_total_combustivel = "Frota total da planilha por combustivel (inclui veiculos sem placa/sem informacao)",
  frota_eletricos_bev = "Veiculos 100% eletricos (BEV): eletrico, eletrico/fonte externa, eletrico/fonte interna, celula a combustivel",
  frota_hibridos_phev = "Hibridos plug-in (PHEV)",
  frota_hibridos_hev = "Hibridos nao plug-in (HEV): hibrido, gasolina/eletrico, gasolina/alcool/eletrico, diesel/eletrico, etanol/eletrico, hibrido/GNV",
  frota_combustao = "Veiculos exclusivamente a combustao (todas as demais categorias com combustivel informado)",
  frota_sem_informacao = "Veiculos sem combustivel informado (sem informacao, nao identificado, nao se aplica, vide observacao)",
  frota_gasolina = "Veiculos somente a gasolina",
  frota_etanol = "Veiculos somente a etanol (categoria ALCOOL)",
  frota_flex = "Veiculos flex (alcool/gasolina)",
  frota_diesel = "Veiculos somente a diesel",
  frota_gnv = "Veiculos com gas natural veicular ou metano (inclusive combinados com outros combustiveis)",
  frota_automoveis = "Automoveis", frota_bondes = "Bondes", frota_caminhoes = "Caminhoes",
  frota_caminhoes_trator = "Caminhoes-trator", frota_caminhonetes = "Caminhonetes", frota_camionetas = "Camionetas",
  frota_chassis_plataforma = "Chassis-plataforma", frota_ciclomotores = "Ciclomotores",
  frota_micro_onibus = "Micro-onibus", frota_motocicletas = "Motocicletas", frota_motonetas = "Motonetas",
  frota_onibus = "Onibus", frota_quadriciclos = "Quadriciclos", frota_reboques = "Reboques",
  frota_semi_reboques = "Semirreboques", frota_side_cars = "Side-cars", frota_outros_tipos = "Outros tipos",
  frota_tratores_esteira = "Tratores de esteira", frota_tratores_rodas = "Tratores de rodas",
  frota_triciclos = "Triciclos", frota_utilitarios = "Utilitarios"
)
salvar_dicionario_variaveis(FONTE, data.frame(
  variavel = names(descricoes), descricao = unname(descricoes), unidade = "veiculos",
  periodicidade = "mensal", fonte_url = URL_FONTE, stringsAsFactors = FALSE
))
