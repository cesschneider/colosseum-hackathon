# comex — Comércio exterior municipal (Comex Stat / MDIC)

## Fonte

- **Órgão**: Secretaria de Comércio Exterior (SECEX) do Ministério do Desenvolvimento, Indústria, Comércio e Serviços (MDIC), sistema Comex Stat.
- **Página principal**: https://comexstat.mdic.gov.br/pt/home
- **Endpoint (download direto, um CSV por ano e fluxo)**:
  - Exportações: `https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/EXP_<ANO>_MUN.csv`
  - Importações: `https://balanca.economia.gov.br/balanca/bd/comexstat-bd/mun/IMP_<ANO>_MUN.csv`
- **Layout bruto**: `;` como separador, textos entre aspas, UTF-8/ASCII. Colunas `CO_ANO`, `CO_MES`, `SH4`, `CO_PAIS`, `SG_UF_MUN`, `CO_MUN`, `KG_LIQUIDO`, `VL_FOB`. Uma linha por município × mês × SH4 × país.
- **`CO_MUN`** é o código IBGE de **7 dígitos** (com dígito verificador), lido como texto e padronizado com `padronizar_codigo7()`. Códigos fora do dicionário oficial (por exemplo, "município não declarado") são descartados no tratamento, com aviso no log.

## Indicadores (`dados/tratados/comex/`)

Bases: `comex_municipal.csv` (município-ano) e `comex_mensal_municipal.csv` (município-ano-mês), com as mesmas variáveis.

| variável | descrição | unidade |
|---|---|---|
| `exportacoes_fob_usd` | Valor total das exportações do município (todos os produtos e destinos) | US$ FOB correntes |
| `exportacoes_agro_fob_usd` | Exportações agropecuárias: produtos dos capítulos 01 a 15 do Sistema Harmonizado (`SH4 < 1601`) | US$ FOB correntes |
| `importacoes_fob_usd` | Valor total das importações do município (todos os produtos e origens) | US$ FOB correntes |
| `importacoes_agro_fob_usd` | Importações agropecuárias, mesma regra `SH4 < 1601` | US$ FOB correntes |
| `saldo_comercial_fob_usd` | `exportacoes_fob_usd − importacoes_fob_usd` | US$ FOB correntes |

Na base anual, os valores são a soma dos meses disponíveis; no ano corrente, a soma cobre apenas os meses já divulgados (ano parcial). A base mensal permite comparar janelas iguais (jan–mês) entre anos.

## Cobertura e periodicidade

- **Territorial**: todos os municípios do Brasil (o recorte é feito somente pelo dicionário oficial do IBGE).
- **Temporal**: 2000 até o ano corrente. O ano corrente é atualizado mensalmente pela fonte (novos meses e revisões dos anteriores); o ano anterior ainda recebe revisões nos primeiros meses do ano seguinte.
- **Periodicidade**: mensal na fonte (arquivo anual acumulado); o painel recebe uma base anual e uma mensal.

## Tamanho e tempo estimados

- Arquivos brutos: exportações de ~22 MB (2000) a ~60 MB (2025) por ano; importações de ~34 MB a ~90 MB. Série completa 2000–2026: **cerca de 2,7 GB** em 54 arquivos.
- Download completo: ~10 a 40 min, conforme a banda (o servidor é rápido e aceita `Range`). Execuções seguintes reutilizam os anos encerrados e rebaixam só o ano corrente (e o anterior, no 1º trimestre): ~100–150 MB.
- Tratamento: leitura seletiva de 5 colunas com `data.table::fread`; ~5 a 15 min para a série completa. Saídas: base anual pequena (~100 mil linhas) e mensal ~1 milhão de linhas (~60–80 MB).

## Dependências

- R ≥ 4.1 com `jsonlite` e `curl` (biblioteca comum) e `data.table` (tratamento).
- Nenhum pacote é instalado pelos scripts (`fontes/00_comum/instalar_dependencias.R`).

## Como rodar

```
Rscript fontes/comex/01_extracao_comex.R     # baixa/reutiliza os brutos em dados/brutos/comex/
Rscript fontes/comex/02_tratamento_comex.R   # gera dados/tratados/comex/*.csv
```

Variáveis úteis para testes: `PAINEL_ANO_INICIAL=2024` (encurta a série), `PAINEL_REBAIXAR=TRUE` (força novo download de tudo), `PAINEL_DADOS=<pasta>` (muda a pasta `dados/`).

## Observações metodológicas

- **Regra agropecuária**: preservada do projeto de origem — `SH4 < 1601`, ou seja, capítulos 01 a 15 do SH (animais vivos, produtos de origem animal, vegetais, gorduras e óleos). A partir do capítulo 16 começam os produtos da indústria alimentar (carnes preparadas, açúcar, bebidas etc.), que ficam fora do agregado "agro".
- **Valores nominais**: US$ FOB correntes, sem deflação nem conversão cambial; a aplicação decide como deflacionar/converter.
- **Zeros e ausências**: as bases trazem apenas os municípios-períodos com alguma operação registrada (exportação ou importação). Dentro dessas linhas, o fluxo sem registro vale `0`, porque os arquivos da aduana são exaustivos (ausência de linha = ausência de operação declarada), e não "dado faltante". Um município ausente em um período não exportou nem importou naquele período.
- **Ano corrente parcial**: comparações anuais devem considerar o número de meses divulgados (use a base mensal). A fonte também revisa retroativamente os meses do ano corrente, por isso o script 01 sempre rebaixa esse arquivo.
- **Município de origem/destino**: o Comex Stat atribui a operação ao município do domicílio fiscal da empresa exportadora/importadora, não necessariamente ao local de produção/consumo (limitação conhecida da fonte).
- O script 01 valida cada download (tamanho mínimo e cabeçalho oficial) antes de substituir o arquivo local; o script 02 rejeita arquivos cujo ano interno difira do nome, com mês fora de 1–12 ou com `VL_FOB` ausente/negativo.
