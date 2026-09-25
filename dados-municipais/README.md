# Painel de Dados Municipais do Brasil — rotinas de coleta e tratamento

Rotinas em R que baixam dados públicos oficiais e os transformam em **bases municipais padronizadas para todo o Brasil** (5.570 municípios, 27 UFs), prontas para alimentar tabelas, gráficos e consolidações em uma aplicação — a ideia de uma "Economática" para dados micro (IBGE, RAIS, CAGED, ANP, SENATRAN, DataSUS, SICONFI etc.).

## Como está organizado

```
fontes/
  00_comum/            biblioteca compartilhada, dicionário de municípios, consolidação do painel
  <fonte>/             01_extracao_<fonte>.R  02_tratamento_<fonte>.R  README.md
  executar_tudo.R      roda tudo em sequência
  CONVENCOES.md        contrato dos scripts e das bases (leia antes de criar uma fonte)
dados/                 gerado pelas rotinas (não versionado)
  auxiliares/          dicionario_municipios.csv, vizinhos_municipios.csv
  brutos/<fonte>/      arquivos originais das fontes
  tratados/<fonte>/    <fonte>_municipal.csv + <fonte>_dicionario_variaveis.csv
  painel/              painel_municipal_long.csv + catalogo_variaveis.csv
```

Toda base tratada tem o mesmo esqueleto: uma linha por município-período, com `codigo_municipio` (IBGE, 7 dígitos), `nome_municipio`, `uf`, `ano`, `mes` (apenas nas mensais) e um indicador numérico por coluna. O script `00_comum/consolidar_painel.R` empilha tudo no formato longo (`fonte, tabela, variavel, codigo_municipio, ano, mes, valor`) e gera o catálogo de variáveis com cobertura observada — é essa camada que a aplicação consome.

## Como rodar

1. Instale o R (4.x) e, uma vez, os pacotes:

```bash
Rscript fontes/00_comum/instalar_dependencias.R
```

2. Gere o dicionário oficial de municípios (IBGE) e, opcionalmente, a lista de municípios vizinhos:

```bash
Rscript fontes/00_comum/01_dicionario_municipios.R
```

3. Rode uma fonte (extração e depois tratamento) ou tudo de uma vez:

```bash
Rscript fontes/ibge_pib_municipal/01_extracao_ibge_pib_municipal.R
```

```bash
Rscript fontes/ibge_pib_municipal/02_tratamento_ibge_pib_municipal.R
```

```bash
Rscript fontes/executar_tudo.R
```

4. Consolide o painel:

```bash
Rscript fontes/00_comum/consolidar_painel.R
```

Variáveis de ambiente úteis para testes rápidos: `PAINEL_UFS="MG,ES"` (só algumas UFs), `PAINEL_ANO_INICIAL=2020` (janela curta), `PAINEL_REBAIXAR=TRUE` (ignora brutos já baixados), `PAINEL_DADOS=<pasta>` (onde gravar os dados).

## Fontes

Cada pasta em `fontes/` tem um `README.md` com endpoints, tabela completa de indicadores, regras de cálculo e armadilhas da fonte. Resumo:

| Pasta | O que traz | Principais indicadores | Cobertura | Periodicidade | Peso |
|---|---|---|---|---|---|
| `ibge_populacao` | População residente (Ipeadata: ESTIMA_PO e POPTOT) | populacao_estimada, populacao_total, populacao (série contínua) | 1992–2026 (+ censos desde 1872) | anual | leve (~40 MB) |
| `ibge_censo_demografico` | Censos 2000, 2010 e 2022 (SIDRA 1552/9514) | população por sexo e faixas etárias, razões de dependência, índice de envelhecimento, razão de sexo | 2000, 2010, 2022 | decenal | leve (2–4 min) |
| `ibge_pib_municipal` | PIB dos Municípios (SIDRA 5938) | pib, vab_* (agro, indústria, serviços, adm. pública), impostos_liquidos, pib_per_capita | 2002–2023 | anual | leve (3–6 min) |
| `ibge_agropecuaria` | PAM e PPM/aquicultura (SIDRA 1612/1613/3940) | valor da produção e área colhida (temporárias, permanentes, total), valor e produção da aquicultura | 1974–2025 (aquicultura 2013+) | anual | médio (30–60 min) |
| `datasus_populacao` | Estimativas populacionais por faixa etária (TabNet) | populacao_0_14 / 15_59 / 60_mais, razões de dependência, índice de envelhecimento | 2000–2025 | anual | leve (~11 MB) |
| `sim` | Mortalidade por município de residência (SIM-DO, microdatasus) | óbitos, idade média ao óbito, homicídios (por sexo), suicídios, causas externas, taxas por 100 mil | 2000–2024 (+ preliminares) | anual | pesado (~3,5 GB, 2–5 h) |
| `ipea_suicidios` | Suicídios (Atlas da Violência via Ipeadata) | suicidios, taxa_suicidios_100mil | 1980–2022 | anual | leve (~60 MB) |
| `caged` | Novo Caged (Ipeadata ADMISNC/DESLIGNC) | admitidos, desligados, saldo (mensal e anual) | 2020-01 até a última competência | mensal | leve (~60 MB) |
| `rais` | RAIS: estabelecimentos e vínculos (FTP do MTE, .7z) | estabelecimentos, vínculos ativos, massa salarial e remuneração média de dezembro, taxa de ocupação, abertura por setor | 2010–2025 | anual | muito pesado (~43 GB; exige 7-Zip) |
| `comex` | Comex Stat: exportações e importações por município | exportações/importações FOB (total e agro, SH cap. 01–15), saldo (anual e mensal) | 2000 até o ano corrente | mensal/anual | médio (~2,7 GB) |
| `siconfi` | Finanças municipais (API SICONFI/STN: DCA e RREO Anexo 06) | receita total/corrente/tributária, transferências, FPM, cota-parte do ICMS, despesa total, pessoal, por função (saúde, educação, infraestrutura…), resultados nominal e primário | DCA 2013+; RREO 2018+ | anual | lento (API 1 req/s: 60–90 h para a série completa; retomável; FINBRA como carga inicial) |
| `bcb_estban` | ESTBAN: estatística bancária municipal (BCB) | agências, operações de crédito, crédito rural e imobiliário, depósitos à vista/poupança/prazo | 2000-01 até o último mês | mensal | médio (~350 MB) |
| `sagicad_bolsa_familia` | Bolsa Família / Auxílio Brasil (MISocial/MDS) | famílias beneficiárias, valor repassado, benefício médio, cobertura por 100 hab. | 2004-01 até o último mês | mensal | leve (~80 MB) |
| `sagicad_cadunico` | Cadastro Único (MISocial/MDS) | pessoas e famílias cadastradas, por faixa de renda, % da população cadastrada | 2012-08 até o último mês | mensal | leve (~80 MB) |
| `inep` | Educação: Censo Escolar, rendimento, Ideb, Enem, Educação Superior | matrículas, escolas, docentes, taxas de aprovação/reprovação/abandono, Ideb por etapa, notas do Enem, ensino superior | 2005/2007 até o mais recente | anual | muito pesado (microdados, dezenas de GB) |
| `anatel` | Banda larga fixa (Anatel) | acessos em dezembro e média mensal, por meio de acesso, densidade por 100 hab. | 2007 até o último ano | anual | médio (zip de ~1 GB) |
| `mtur` | Cadastur: hospedagem e guias (MTur) | meios de hospedagem, leitos, unidades habitacionais, guias de turismo | 2006 até o ano corrente | anual | leve (~200 MB) |
| `mapbiomas` | Cobertura e uso da terra (MapBiomas, coleção vigente) | área por classe (floresta, agropecuária, pastagem, agricultura, urbana, água…) | 1985–2025 | anual | leve (um xlsx) |
| `snis_sinisa` | Saneamento (SNIS até 2022; SINISA 2023+) | população atendida e volumes de água e esgoto, economias, paralisações, índices de atendimento e tratamento | 2000–2022 (exportação manual) e 2023+ (automático) | anual | leve |
| `senatran` | Frota de veículos por município (SENATRAN/RENAVAM, planilhas mensais) | frota total, por combustível (elétricos BEV, híbridos PHEV/HEV, combustão, flex, gasolina, etanol, diesel, GNV) e por 21 tipos de veículo | 2016-07 até o mês mais recente (2013–2016-06 em formatos não suportados) | mensal | médio (~250 MB, ~250 xlsx) |
| `anp` | Vendas anuais de combustíveis por município e preços de revenda (ANP) | vendas em m³ por produto (etanol, gasolina C, diesel, GLP em kg, QAV…); preço médio mensal de gasolina, etanol, diesel, GNV e GLP nos municípios pesquisados | vendas 1990–2024; preços 2013 até o último semestre (configurável desde 2004) | anual / mensal | médio (~1–1,5 GB para preços) |

Sem código IBGE na fonte (SENATRAN, ANP, Cadastur) a junção é por nome normalizado + UF, com taxa de casamento registrada no log.

## Princípios

- **Universo nacional.** Nenhum script filtra UF ou lista de municípios; o recorte é feito pela aplicação.
- **Bruto preservado, tratado reproduzível.** O 01 só baixa; o 02 sempre pode ser rodado de novo a partir dos brutos.
- **Valores nominais.** Deflação e taxas per capita são calculadas na camada de análise (a biblioteca oferece `deflator_ipca_anual()` e população do Ipeadata quando um indicador precisa de denominador).
- **Sem dependências ocultas.** Cada fonte roda sozinha; só o dicionário de municípios é compartilhado.
- **Sem instalação automática de pacotes, sem caminhos absolutos, sem dados de terceiros embutidos.**
