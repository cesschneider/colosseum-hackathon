# caged — Admissões, desligamentos e saldo de empregos celetistas (Novo Caged via Ipeadata)

## Fonte

- **Órgão produtor:** Ministério do Trabalho e Emprego — Novo Cadastro Geral de Empregados e Desempregados (Novo Caged, dados do Caged + eSocial + Empregador Web), estatísticas "sem ajuste".
- **Canal de acesso:** API OData v4 do Ipeadata, séries `ADMISNC` (admissões) e `DESLIGNC` (desligamentos), nível territorial "Municípios".
- **Endpoint:** `https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='<serie>')` (valores) e `.../Metadados(SERCODIGO='<serie>')` (metadados). Cada chamada devolve a série integral (Brasil, regiões, UFs, áreas metropolitanas e municípios) em uma única resposta JSON.

## Indicadores

### `dados/tratados/caged/caged_municipal.csv` — mensal (município-ano-mês)

| variável | descrição | unidade |
|---|---|---|
| `admitidos` | Empregados celetistas admitidos no mês (`ADMISNC`) | pessoas |
| `desligados` | Empregados celetistas desligados no mês (`DESLIGNC`, contagem positiva) | pessoas |
| `saldo` | `admitidos - desligados`; vazio quando uma das séries não informa a competência | pessoas |

### `dados/tratados/caged/caged_anual_municipal.csv` — anual (município-ano)

| variável | descrição | unidade |
|---|---|---|
| `admitidos_ano` | Soma dos admitidos nos meses com admitidos e desligados informados | pessoas |
| `desligados_ano` | Soma dos desligados nos mesmos meses | pessoas |
| `saldo_ano` | `admitidos_ano - desligados_ano` | pessoas |
| `meses_informados` | Meses do ano com as duas séries informadas (< 12 = ano parcial ou com lacunas) | meses |

O dicionário de variáveis (`caged_dicionario_variaveis.csv`) cobre as duas tabelas.

## Cobertura e periodicidade

- **Territorial:** todos os municípios do Brasil (≈5.570; o dicionário oficial do painel define o universo).
- **Temporal:** 2020-01 até a última competência divulgada (2026-07 na consulta de setembro/2026). Defasagem de divulgação variável (1–2 meses). `PAINEL_ANO_INICIAL` recorta o início para testes.
- **Periodicidade:** mensal (base anual derivada).

### Por que a série começa em 2020

O Ipeadata **não possui séries municipais do Caged antigo (2004-2019)**. Verificação feita no endpoint de metadados (`Metadados?$filter=substringof('CAGED',SERCODIGO)` e filtros por fonte/nome na base "Regional"): as séries do Caged antigo (`CAGED12_ADMIS`, `CAGED12_DESLIG`, `CAGED12_SALDO12`, hoje inativas) e as do Novo Caged com/sem ajuste (`CAGED12_*N12`, `CAGED12_*NAJU12`) pertencem à base "Macroeconômico", nível Brasil apenas. Na base "Regional" existem somente `ADMISNC` e `DESLIGNC`. Cobrir 2004-2019 por município exigiria outra fonte (microdados/estatísticas do Caged no PDET/MTE), com quebra metodológica em relação ao Novo Caged (universo declarante, eSocial e prazos de declaração diferentes).

## Tamanho e tempo estimado

- Cada série bruta: ~443 mil linhas (440 mil municipais), ~31 MB em CSV, 3–4 min de download (resposta JSON única de dezenas de MB; `PAINEL_TIMEOUT` controla o limite).
- Etapa 02 (R base): 1–2 min. Base mensal: ~440 mil linhas; base anual: ~39 mil linhas.

## Dependências

R base + `jsonlite` + `curl` (biblioteca comum). Não usa `data.table`.

## Como rodar

```
Rscript fontes/caged/01_extracao_caged.R
Rscript fontes/caged/02_tratamento_caged.R
```

Teste rápido da etapa 02: `PAINEL_UFS=AC Rscript fontes/caged/02_tratamento_caged.R` (o script 01 sempre baixa o Brasil inteiro).

## Observações metodológicas

- **Snapshot integral com revisões retroativas.** A API devolve toda a série em URL fixa e o MTE revisa competências já divulgadas (declarações fora do prazo); a última competência é a mais sujeita a revisão. O script 01 rebaixa as séries a cada execução (reutiliza apenas um arquivo baixado no mesmo dia; `PAINEL_REBAIXAR=TRUE` força). Os metadados (`*_metadados.csv`) registram a data de atualização no Ipeadata.
- **Séries "sem ajuste".** `ADMISNC`/`DESLIGNC` são as estatísticas sem os ajustes de declarações fora do prazo; os totais podem diferir das séries "com ajuste" divulgadas pelo MTE em nível nacional.
- **Sinal e saldo.** A API entrega desligamentos como contagem positiva; a base mantém esse sinal e calcula `saldo = admitidos - desligados`.
- **Ausência não é zero.** A API traz zeros explícitos para municípios sem movimento; quando uma competência não aparece para um município em uma das séries, o valor fica `NA` e o saldo também. As competências com menos municípios que o máximo observado são listadas no log (em 2020-2023 faltam alguns municípios por mês; a série municipal contém 5.571 códigos, um deles fora do dicionário oficial e descartado).
- **Base anual.** Os totais anuais somam apenas meses com as duas séries informadas, de modo que `saldo_ano = admitidos_ano - desligados_ano` sempre; `meses_informados` identifica anos parciais (ano corrente) ou com lacunas.
- **Universo:** empregados regidos pela CLT (inclui temporários, avulsos, intermitentes e agentes públicos celetistas), por município do estabelecimento.
