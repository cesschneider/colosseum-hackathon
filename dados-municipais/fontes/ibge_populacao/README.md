# ibge_populacao — População residente municipal (IBGE via Ipeadata)

## Fonte

- **Órgão produtor:** IBGE — Estimativas da População (1º de julho) e Censos Demográficos / Contagem da População 2007.
- **Canal de acesso:** API OData v4 do Ipeadata, séries `ESTIMA_PO` e `POPTOT`, nível territorial "Municípios".
- **Endpoint:** `https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='<serie>')` (valores) e `.../Metadados(SERCODIGO='<serie>')` (metadados). Cada chamada devolve a série integral, em todos os níveis territoriais, em uma única resposta JSON.

## Indicadores (`dados/tratados/ibge_populacao/ibge_populacao_municipal.csv`)

Uma linha por município-ano (`codigo_municipio`, `nome_municipio`, `uf`, `ano`).

| variável | descrição | unidade |
|---|---|---|
| `populacao_estimada` | População residente estimada em 1º de julho (série `ESTIMA_PO`) | habitantes |
| `populacao_total` | População residente total apurada nos Censos (1872…2022) e na Contagem 2007 (série `POPTOT`); vazia nos demais anos | habitantes |
| `populacao` | População de referência do ano: `populacao_total` quando o ano é censitário, `populacao_estimada` nos demais anos | habitantes |

O dicionário de variáveis é gravado em `ibge_populacao_dicionario_variaveis.csv`.

## Cobertura e periodicidade

- **Territorial:** todos os municípios do Brasil (o dicionário oficial do painel define o universo; códigos de municípios extintos ou não instalados são descartados na etapa 02).
- **Temporal:** toda a série disponível no Ipeadata. `ESTIMA_PO`: 1992 até o último ano estimado (2026 na consulta de setembro/2026), sem os anos 1996, 2007, 2010, 2022 e 2023. `POPTOT`: anos censitários 1872, 1890, 1910, 1920, 1940, 1950, 1960, 1970, 1980, 1991, 1996, 2000, 2007, 2010 e 2022. `PAINEL_ANO_INICIAL` recorta o início para testes.
- **Periodicidade:** anual (`ESTIMA_PO`); decenal/censitária (`POPTOT`). O último ano disponível pode ser anterior ao ano corrente, conforme o calendário do IBGE e do Ipeadata.

## Tamanho e tempo estimado

- `ipeadata_ESTIMA_PO.csv`: ~380 mil linhas em todos os níveis (164 mil municipais), ~27 MB, ~1 min de download.
- `ipeadata_POPTOT.csv`: ~156 mil linhas (50 mil municipais), ~11 MB, 0,5–2 min de download.
- Etapa 02 (R base): menos de 1 min. Base tratada: ~200 mil linhas.

## Dependências

R base + `jsonlite` + `curl` (biblioteca comum). Não usa `data.table` nem o pacote `ipeadatar`.

## Como rodar

```
Rscript fontes/ibge_populacao/01_extracao_ibge_populacao.R
Rscript fontes/ibge_populacao/02_tratamento_ibge_populacao.R
```

Teste rápido: `PAINEL_UFS=AC Rscript fontes/ibge_populacao/02_tratamento_ibge_populacao.R` (o script 01 sempre baixa o Brasil inteiro, pois a API não permite recorte por UF na mesma URL).

## Observações metodológicas

- **Snapshots com revisão retroativa.** A API devolve a série completa em URL fixa e o IBGE/Ipeadata revisam estimativas já divulgadas (por exemplo, após o Censo 2022). O script 01 rebaixa as séries a cada execução; só reutiliza um arquivo baixado no mesmo dia (`PAINEL_REBAIXAR=TRUE` força novo download). Os metadados da série (`*_metadados.csv`) registram a data de atualização no Ipeadata.
- **Somente o nível "Municípios"** entra no tratamento; a resposta também traz Brasil, regiões, UFs, meso/microrregiões e áreas mínimas comparáveis (AMC).
- **Ausência não é zero.** Valores zero ou negativos (7 registros históricos em `POPTOT`) viram `NA`; anos sem estimativa permanecem vazios. Nada é interpolado.
- **Lacunas de `ESTIMA_PO`:** o Ipeadata não traz estimativa de 1º de julho para 1996, 2007, 2010, 2022 (anos de Contagem/Censo, cobertos por `POPTOT`) nem para 2023 (nenhuma das duas séries; o ano fica sem linha). Em 2000 as duas séries coexistem.
- **Regra da coluna `populacao`:** usa a população censitária quando ela existe para o ano (1996, 2000, 2007, 2010, 2022 e Censos anteriores) e a estimativa de 1º de julho nos demais anos, o que produz uma série anual contínua de 1992 a 2026, exceto 2023.
- **Notas do IBGE reproduzidas no Ipeadata:** em 2007 os totais vêm da Contagem da População (referência 1º de abril) para 5.435 municípios e de estimativas para os demais 128 + DF; em 2010 há tratamento de domicílios fechados. As datas de referência do Censo (1º de agosto de 2022, por exemplo) diferem da data das estimativas (1º de julho).
- **Malha municipal:** a série usa o universo definido pelo IBGE em cada levantamento; municípios criados depois não têm valores nos anos anteriores à instalação.
