# ipea_suicidios — Óbitos por suicídio e taxa por 100 mil habitantes (Ipea/Atlas da Violência via Ipeadata)

## Fonte

- **Órgão produtor:** Ministério da Saúde / SVS / CGIAE — Sistema de Informações sobre Mortalidade (SIM), compilado pelo Ipea (Atlas da Violência) e distribuído pelo Ipeadata.
- **Canal de acesso:** API OData v4 do Ipeadata, série `AVIOL12_SUICID` ("Número de suicídios", anual, nível "Municípios"). O denominador da taxa é a série `ESTIMA_PO` (população residente estimada em 1º de julho, IBGE), baixada pela própria fonte para não depender de `ibge_populacao`.
- **Endpoint:** `https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='<serie>')` (valores) e `.../Metadados(SERCODIGO='<serie>')` (metadados).

## Indicadores (`dados/tratados/ipea_suicidios/ipea_suicidios_municipal.csv`)

Uma linha por município-ano (`codigo_municipio`, `nome_municipio`, `uf`, `ano`).

| variável | descrição | unidade |
|---|---|---|
| `suicidios` | Óbitos por lesões autoprovocadas voluntariamente (CID-10 X60-X84; CID-9 E950-E959 até 1995), por município de residência | óbitos |
| `taxa_suicidios_100mil` | `suicidios / populacao_estimada (ESTIMA_PO) × 100.000`; vazia quando não há população para o município-ano | óbitos por 100 mil habitantes |

O dicionário de variáveis é gravado em `ipea_suicidios_dicionario_variaveis.csv`.

## Cobertura e periodicidade

- **Territorial:** todos os municípios do Brasil (5.569 municípios na série; nos anos 1980 apenas ~1.200 municípios têm registro, crescendo até ~5.565 a partir dos anos 2010).
- **Temporal:** 1980 até o último ano divulgado (2022 na consulta de setembro/2026; o SIM tem defasagem de 2 a 3 anos). A taxa só existe a partir de 1992, início da série `ESTIMA_PO`. `PAINEL_ANO_INICIAL` recorta o início para testes.
- **Periodicidade:** anual.

## Tamanho e tempo estimado

- `ipeadata_AVIOL12_SUICID.csv`: ~425 mil linhas em todos os níveis (201 mil municipais), ~30 MB, ~1,5 min de download.
- `ipeadata_ESTIMA_PO.csv`: ~380 mil linhas (164 mil municipais), ~27 MB, ~1 min.
- Etapa 02 (R base): menos de 1 min. Base tratada: ~200 mil linhas.

## Dependências

R base + `jsonlite` + `curl` (biblioteca comum). Não usa `data.table`.

## Como rodar

```
Rscript fontes/ipea_suicidios/01_extracao_ipea_suicidios.R
Rscript fontes/ipea_suicidios/02_tratamento_ipea_suicidios.R
```

Teste rápido da etapa 02: `PAINEL_UFS=AC Rscript fontes/ipea_suicidios/02_tratamento_ipea_suicidios.R` (o script 01 sempre baixa o Brasil inteiro).

## Observações metodológicas

- **Zero é informação.** Mais da metade dos registros municipais são zeros explícitos (municípios pequenos sem óbito no ano) e são preservados; a ausência de linha (município sem registro no ano) permanece ausente, nunca é convertida em zero.
- **Quebra de classificação em 1996:** de 1979 a 1995 a série usa CID-9 (E950-E959); a partir de 1996, CID-10 (X60-X84). Compare com cautela séries que cruzam 1995/1996.
- **Denominador da taxa:** população residente estimada em 1º de julho (`ESTIMA_PO`, IBGE via Ipeadata), a mesma série usada pela fonte `ibge_populacao`, baixada de forma independente nesta pasta. `ESTIMA_PO` começa em 1992 e não cobre 1996, 2007, 2010 e 2022 (anos de Contagem/Censo): nesses anos e antes de 1992 a coluna `suicidios` existe, mas `taxa_suicidios_100mil` fica vazia. Se o painel precisar da taxa nesses anos, o complemento natural é a população censitária (`POPTOT`, disponível em `ibge_populacao`). Taxas de municípios muito pequenos são instáveis (um óbito pode representar dezenas de casos por 100 mil).
- **Snapshots com revisão retroativa.** O SIM é atualizado (óbitos investigados, causas reclassificadas) e o Ipeadata republica a série inteira; o script 01 rebaixa as séries a cada execução (reutiliza apenas um arquivo baixado no mesmo dia; `PAINEL_REBAIXAR=TRUE` força). Os metadados (`*_metadados.csv`) registram a data de atualização no Ipeadata.
- **Somente o nível "Municípios"** entra no tratamento; a resposta também traz Brasil, regiões, UFs, meso/microrregiões e áreas mínimas comparáveis. Códigos fora do dicionário oficial (municípios extintos) são descartados.
- **Sigilo:** o Ipeadata publica contagens integrais sem supressão de células pequenas; a divulgação de valores 1-3 em municípios pequenos deve seguir a política de privacidade do painel.
