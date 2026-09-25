# IBGE – Produto Interno Bruto dos Municípios (`ibge_pib_municipal`)

## Fonte

- **Órgão:** IBGE, Coordenação de Contas Nacionais, em parceria com os órgãos estaduais de estatística.
- **Conjunto:** Produto Interno Bruto dos Municípios – tabela SIDRA **5938** ("Produto interno bruto a preços correntes, impostos, líquidos de subsídios, sobre produtos a preços correntes e valor adicionado bruto a preços correntes total e por atividade econômica, e respectivas participações").
- **Página:** https://www.ibge.gov.br/estatisticas/economicas/contas-nacionais/9088-produto-interno-bruto-dos-municipios.html
- **Tabela SIDRA:** https://sidra.ibge.gov.br/tabela/5938

## Endpoints

| Uso | URL |
|---|---|
| Descoberta dos anos publicados | `https://servicodados.ibge.gov.br/api/v3/agregados/5938/periodos` |
| Valores (uma UF por vez, blocos de anos) | `https://apisidra.ibge.gov.br/values/t/5938/n6/in%20n3%20<cod_uf>/v/37,498,513,517,525,543,6575/p/<anos>?formato=json` |
| População – estimativas anuais | `https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='ESTIMA_PO')` |
| População – censos e contagens | `https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='POPTOT')` |

A API SIDRA recusa consultas com mais de ~50 mil valores (HTTP 400). O script 01 descobre os anos publicados e os divide em blocos dimensionados pela UF com mais municípios (MG, 853 municípios × 7 variáveis → 8 anos por bloco), consultando cada bloco UF a UF.

## Indicadores (`ibge_pib_municipal_municipal.csv`)

Uma linha por município-ano. Chaves: `codigo_municipio` (7 dígitos), `nome_municipio`, `uf`, `ano`.

| variável | descrição | unidade |
|---|---|---|
| `pib` | Produto Interno Bruto a preços correntes (variável SIDRA 37) | R$ mil correntes |
| `vab_total` | Valor adicionado bruto total (498) | R$ mil correntes |
| `vab_agropecuaria` | VAB da agropecuária (513) | R$ mil correntes |
| `vab_industria` | VAB da indústria (517) | R$ mil correntes |
| `vab_servicos` | VAB dos serviços, exclusive administração, defesa, educação e saúde públicas e seguridade social (6575) | R$ mil correntes |
| `vab_adm_publica` | VAB da administração, defesa, educação e saúde públicas e seguridade social (525) | R$ mil correntes |
| `impostos_liquidos` | Impostos, líquidos de subsídios, sobre produtos (543) | R$ mil correntes |
| `pib_per_capita` | `pib × 1000 / população residente` (população do Ipeadata: POPTOT nos anos de censo/contagem, ESTIMA_PO nos demais) | R$ correntes por habitante |

Identidades contábeis: `vab_total = vab_agropecuaria + vab_industria + vab_servicos + vab_adm_publica` e `pib = vab_total + impostos_liquidos` (diferenças de arredondamento de poucos mil reais são normais; o script apenas avisa quando a diferença passa de 5 mil reais).

## Cobertura temporal e periodicidade

- **Anos:** 2002 até o último ano publicado (2023 na divulgação vigente). O script não fixa o ano final: usa a lista de períodos da API de agregados.
- **Atenção à cobertura por variável:** na divulgação atual os componentes (`vab_*`, `impostos_liquidos`) terminam em **2021**; para 2022 e 2023 o IBGE publicou apenas o PIB total (as demais variáveis vêm como `...` e ficam `NA`). A abertura setorial desses anos deverá aparecer na nova série do Sistema de Contas Nacionais.
- **`pib_per_capita`:** disponível enquanto houver população no Ipeadata para o ano (hoje, 2002–2022; 2023 fica `NA` por falta de estimativa populacional publicada).
- **Periodicidade:** anual, divulgação em dezembro com defasagem de cerca de dois anos; a cada divulgação o IBGE também revisa os anos anteriores.
- **Municípios:** todos os 5.570. Municípios instalados depois de 2002 (por exemplo, os cinco criados em 2013) só aparecem a partir do ano em que passam a ter dados; linhas sem nenhum valor são descartadas.

## Tamanho e tempo estimados

- SIDRA: 27 UFs × 3 blocos de anos = 81 requisições, ~860 mil valores, cerca de 300 MB de JSON transferidos; bruto gravado em RDS comprimido (~15 MB).
- Ipeadata: ESTIMA_PO (~165 mil linhas municipais, ~15 MB) e POPTOT (~50 mil linhas, ~5 MB), gravados em CSV.
- Tempo total típico: 3 a 6 minutos, dependendo da API.

## Dependências

R base + `jsonlite` + `curl` (biblioteca comum). Não usa `sidrar` nem `ipeadatar`. `data.table` é opcional (acelera a leitura/gravação de CSV quando instalado).

## Como rodar

```bash
Rscript fontes/ibge_pib_municipal/01_extracao_ibge_pib_municipal.R
Rscript fontes/ibge_pib_municipal/02_tratamento_ibge_pib_municipal.R
```

Saídas:

- `dados/brutos/ibge_pib_municipal/sidra_5938_pib_municipal.rds` – retorno da API SIDRA tal como recebido (valores em texto, inclusive `-` e `...`), mais `sidra_5938_assinatura.txt` (UFs e anos da coleta);
- `dados/brutos/ibge_pib_municipal/ipeadata_ESTIMA_PO.csv` e `ipeadata_POPTOT.csv`;
- `dados/tratados/ibge_pib_municipal/ibge_pib_municipal_municipal.csv` e `ibge_pib_municipal_dicionario_variaveis.csv`.

Reutilização: o bruto do SIDRA é reaproveitado quando as UFs ativas e a lista de anos publicados são as mesmas da coleta anterior; quando o IBGE publica um ano novo, a coleta é refeita automaticamente. `PAINEL_REBAIXAR=TRUE` força nova coleta. Para testes: `PAINEL_UFS=AC` e/ou `PAINEL_ANO_INICIAL=2018`.

## Observações metodológicas

- Valores **nominais** (preços correntes), como divulgados; a aplicação deflaciona quando necessário.
- Símbolos do SIDRA: `-` é zero absoluto (por exemplo, VAB agropecuário nulo) e vira `0`; `...` (não disponível), `..` (não se aplica) e `X` (omitido) viram `NA`. Nunca se converte indisponibilidade em zero.
- `pib_per_capita` é calculado com a população residente do Ipeadata (série IBGE): `POPTOT` nos anos de censo e contagem (2000, 2007, 2010, 2022) e `ESTIMA_PO` (estimativas de 1º de julho) nos demais. A tabela 5938 também traz um PIB per capita oficial (variável 6376), calculado pelo IBGE com as estimativas populacionais vigentes em cada divulgação; pequenas diferenças em relação ao valor aqui calculado são esperadas.
- O per capita é `NA` quando não há população publicada para o ano.
