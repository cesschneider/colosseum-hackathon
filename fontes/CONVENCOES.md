# Convenções dos scripts de fonte

Este repositório reúne rotinas de coleta e tratamento de dados públicos **municipais para todo o Brasil** (5.570 municípios, 27 UFs). Cada fonte de dados vive em sua própria pasta dentro de `fontes/` e produz bases tratadas em um esquema único, consumido pela camada de aplicação (tabelas, gráficos e consolidações).

## 1. Estrutura

```
fontes/
  00_comum/                 biblioteca compartilhada (config.R, funcoes_comuns.R,
                            dicionário de municípios, vizinhos, consolidação do painel)
  <fonte>/
    01_extracao_<fonte>.R   baixa e preserva os arquivos brutos (sem transformar)
    02_tratamento_<fonte>.R lê os brutos, padroniza e grava a base municipal
    README.md               o que é a fonte, indicadores, cobertura, como rodar
  executar_tudo.R           roda tudo em sequência
dados/                      gerado; nunca versionado
  auxiliares/               dicionario_municipios.csv, vizinhos_municipios.csv
  brutos/<fonte>/           arquivos originais da fonte
  tratados/<fonte>/         <fonte>_municipal.csv + <fonte>_dicionario_variaveis.csv
  painel/                   painel_municipal_long.csv + catalogo_variaveis.csv
  logs/                     execucoes.csv
```

Nomes de pasta e de fonte: minúsculas, sem acento, `snake_case` (ex.: `ibge_pib_municipal`, `sagicad_bolsa_familia`).

## 2. Bloco inicial obrigatório de todo script

```r
# -*- coding: UTF-8 -*-
# ------------------------------------------------------------------------------
# SCRIPT: 01_extracao_<fonte>.R
# FONTE: <órgão> - <conjunto de dados>
# OBJETIVO: ...
# COBERTURA: Brasil, todos os municípios; <ano inicial> até o mais recente
# PERIODICIDADE: anual | mensal
# ENDPOINT: <url>
# SAÍDAS: dados/brutos/<fonte>/...
# COMO EXECUTAR: Rscript fontes/<fonte>/01_extracao_<fonte>.R
# ------------------------------------------------------------------------------
.arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
.dir <- if (length(.arg)) dirname(normalizePath(sub("^--file=", "", .arg[1]), winslash = "/")) else getwd()
source(file.path(dirname(.dir), "00_comum", "funcoes_comuns.R"), encoding = "UTF-8")
preparar_ambiente(c("data.table"))   # pacotes específicos da fonte
FONTE <- "<fonte>"
```

Comentários e mensagens dentro do código: **sem acentos** (evita problemas de encoding entre Windows/Linux). Acentos são bem-vindos nos `README.md`.

## 3. O que a biblioteca comum oferece (`00_comum/funcoes_comuns.R`)

| Função | Uso |
|---|---|
| `preparar_ambiente(pacotes)` | opções, locale UTF-8, checagem de pacotes, pastas de dados |
| `dir_brutos(FONTE)`, `dir_tratados(FONTE)` | pastas padrão da fonte (criadas se preciso) |
| `baixar_arquivo(url, destino, validador=)` | download atômico com retentativas e reutilização |
| `obter_texto_url`, `obter_json_url`, `listar_links_pagina` | leitura de páginas/APIs, descoberta de links |
| `descompactar_zip`, `listar_membros_zip` | zips |
| `escrever_csv`, `ler_csv` | CSV UTF-8, separador `,` e decimal `.` |
| `carregar_dicionario_municipios()` | 5.570 municípios: `codigo_municipio` (7), `codigo6`, `nome_municipio`, `uf`, `cod_uf`, `regiao`, micro/meso, regiões imediata/intermediária, `nome_normalizado` |
| `padronizar_codigo7`, `codigo6_para_7`, `uf_por_codigo` | códigos IBGE |
| `juntar_dicionario(df)` | acrescenta `nome_municipio` e `uf` oficiais pelo código |
| `juntar_por_nome_uf(df, col_nome, col_uf)` | fontes sem código IBGE (casa por nome normalizado + UF) |
| `normalizar_nome`, `remover_acentos`, `para_numero`, `mes_pt_para_numero` | texto/números |
| `sidra_consultar(tabela, variaveis, periodos, classificacoes)` + `sidra_padronizar` | API SIDRA, todos os municípios, uma UF por vez |
| `ipeadata_valores`, `ipeadata_municipal`, `ipeadata_metadados` | API Ipeadata OData |
| `bcb_sgs(serie)`, `deflator_ipca_anual(ano_base)` | SGS/BCB e deflator IPCA |
| `salvar_base_tratada(FONTE, df, nome, mensal)` | valida e grava `dados/tratados/<fonte>/<nome>.csv` |
| `salvar_dicionario_variaveis(FONTE, dic)` | grava o catálogo de variáveis da fonte |
| `registrar_execucao`, `log_msg` | log simples |
| `UFS`, `UFS_ATIVAS`, `ANO_ATUAL`, `ano_inicial_efetivo(ano)` | cobertura territorial/temporal (config) |

Variáveis de ambiente para testes rápidos: `PAINEL_UFS="MG,ES"`, `PAINEL_ANO_INICIAL=2020`, `PAINEL_REBAIXAR=TRUE`, `PAINEL_DADOS=<pasta>`.

## 4. Contrato da base tratada (`02_tratamento_<fonte>.R`)

Uma linha por **município-período**, formato largo:

| coluna | tipo | regra |
|---|---|---|
| `codigo_municipio` | texto, 7 dígitos | código IBGE oficial, sempre presente |
| `nome_municipio` | texto | vindo do dicionário oficial |
| `uf` | texto (2) | vindo do dicionário oficial |
| `ano` | inteiro | |
| `mes` | inteiro 1–12 | apenas em bases mensais (`mensal = TRUE`) |
| demais colunas | numéricas | um indicador por coluna, `snake_case`, sem acento |

Regras:

- Universo = **todos os municípios do Brasil**. Nenhum filtro de UF, lista de municípios, "grupos" ou classificações territoriais de projeto.
- Valores monetários ficam **nominais** (a aplicação deflaciona quando quiser); se a fonte já entrega deflacionado, documentar no dicionário.
- Faltantes ficam `NA` (vazio no CSV). Nunca preencher com zero o que a fonte não informa.
- Chave `(codigo_municipio, ano[, mes])` única — `salvar_base_tratada` valida.
- Uma fonte pode gravar mais de uma base (ex.: `inep_ideb_municipal`, `inep_censo_escolar_municipal`), cada uma com o sufixo `_municipal`.
- Toda base vem acompanhada do dicionário de variáveis (`salvar_dicionario_variaveis`): `variavel, descricao, unidade, periodicidade, nivel, tabela, fonte_url`.

## 5. O que os scripts NÃO devem conter

- Nomes de clientes, empresas, consultorias, projetos comerciais ou pessoas.
- Caminhos absolutos, OneDrive, `C:/Users/...`, `setwd()`.
- Listas fixas de municípios, universos "esperados" (ex.: número fixo de municípios) ou classificações de municípios de um projeto.
- Lógica de "continuidade" com entregas anteriores, reconciliação com planilhas legadas, manifestos de auditoria, hashes por execução, planilhas-modelo de Excel.
- Instalação automática de pacotes.

## 6. Checklist antes de dar a fonte como pronta

1. `Rscript -e "parse('fontes/<fonte>/01_extracao_<fonte>.R')"` sem erro (idem para o 02).
2. `01` roda sozinho e só baixa; `02` roda sozinho a partir dos brutos.
3. `02` chama `salvar_base_tratada` e `salvar_dicionario_variaveis`.
4. `README.md` da fonte lista indicadores, cobertura, periodicidade, endpoint e observações (tamanho dos downloads, dependências como 7-Zip).
5. `grep -ri` por termos proibidos (seção 5) vazio.
