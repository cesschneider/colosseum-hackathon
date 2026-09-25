# Fonte `anp` — Vendas de combustíveis por município e preços de revenda (ANP)

**Órgão:** Agência Nacional do Petróleo, Gás Natural e Biocombustíveis (ANP) — Dados Abertos.
Duas bases distintas são produzidas a partir de dois conjuntos:

1. **Vendas anuais de combustíveis por município** (vendas das distribuidoras, 1990–último ano publicado) →
   `anp_vendas_municipal.csv` (município-ano).
2. **Levantamento de Preços de Combustíveis** (pesquisa semanal por posto, arquivos semestrais) →
   `anp_precos_municipal.csv` (município-mês, **apenas municípios pesquisados**).

## Endpoints

- Vendas: `https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/vdpb/vaehdpm/<produto>/vendas-anuais-de-<produto>-por-municipio.csv`
  para `etanol-hidratado, gasolina-c, oleo-diesel, glp, oleo-combustivel, gasolina-de-aviacao, querosene-de-aviacao, querosene-iluminante, asfalto`
  (página: `.../dados-abertos/vendas-de-derivados-de-petroleo-e-biocombustiveis`). CSV `;`, UTF-8 com BOM,
  colunas `ANO; GRANDE REGIÃO; UF; PRODUTO; CÓDIGO IBGE; MUNICÍPIO; VENDAS` (GLP: `P13; OUTROS`).
- Preços: página `.../dados-abertos/serie-historica-de-precos-de-combustiveis`, arquivos
  `.../arquivos/shpc/dsas/ca/ca-<ANO>-<01|02>.zip` (2022-02 em diante; `.csv` direto de 2004 a 2021;
  o 1º semestre de 2022 chama-se `precos-semestrais-ca.zip`) e `.../shpc/dsas/glp/glp-<ANO>-<sem>.csv`.
  CSV `;`, decimal `,`, colunas `Regiao - Sigla; Estado - Sigla; Municipio; Revenda; CNPJ da Revenda; ...; Produto; Data da Coleta; Valor de Venda; Valor de Compra; Unidade de Medida; Bandeira`.
  Os links são descobertos na página (nomes fora do padrão recebem o semestre pela ordem decrescente da lista);
  períodos ausentes tentam o padrão de URL (zip e, se falhar, csv).

## Saídas e indicadores

### `anp_vendas_municipal.csv` (anual)

| variável | descrição | unidade |
|---|---|---|
| `vendas_etanol_hidratado_m3` | vendas de etanol hidratado | m³ |
| `vendas_gasolina_c_m3` | vendas de gasolina C | m³ |
| `vendas_oleo_diesel_m3` | vendas de óleo diesel | m³ |
| `vendas_oleo_combustivel_m3` | vendas de óleo combustível | m³ |
| `vendas_gasolina_aviacao_m3` | vendas de gasolina de aviação | m³ |
| `vendas_querosene_aviacao_m3` | vendas de querosene de aviação | m³ |
| `vendas_querosene_iluminante_m3` | vendas de querosene iluminante | m³ |
| `vendas_asfalto_m3` | vendas de asfalto | m³ (a confirmar nos metadados; ver abaixo) |
| `vendas_glp_kg` | vendas de GLP, todos os vasilhames (P13 + outros) | kg |
| `vendas_glp_p13_kg` | vendas de GLP em botijões de 13 kg | kg |

### `anp_precos_municipal.csv` (mensal)

| variável | descrição | unidade |
|---|---|---|
| `preco_medio_gasolina` | média do valor de venda ao consumidor, gasolina comum | R$/litro (nominal) |
| `preco_medio_gasolina_aditivada` | idem, gasolina aditivada | R$/litro |
| `preco_medio_etanol` | idem, etanol hidratado | R$/litro |
| `preco_medio_diesel` | idem, diesel (S500) | R$/litro |
| `preco_medio_diesel_s10` | idem, diesel S10 | R$/litro |
| `preco_medio_gnv` | idem, GNV | R$/m³ |
| `preco_medio_glp_p13` | idem, GLP botijão de 13 kg | R$/13 kg |
| `n_coletas_total` | número de coletas (postos × semanas × produtos) no município-mês | coletas |

Média simples das coletas do mês (não ponderada por volume). Valores nominais.

## Cobertura temporal e periodicidade

- Vendas: 1990 (GLP 1992) até 2024 nas versões atuais dos CSVs; anual; um CSV acumulado por produto,
  rebaixado quando o bruto tem mais de 30 dias.
- Preços: `ANO_INICIAL_PRECOS` padrão 2013 (série existe desde 2004; ajuste via `PAINEL_ANO_INICIAL` só recua até 2013 —
  para antes disso altere `ano_inicial_efetivo(2013L)` nos dois scripts). Arquivos semestrais; o semestre corrente só
  existe depois de encerrado (mensais do semestre em curso não são usados). Arquivos do ano corrente são sempre rebaixados.

## Tamanho e tempo

- Vendas: 9 CSVs de 1–10 MB (≈ 60 MB no total).
- Preços: `ca-<ano>-<sem>.zip` ≈ 8 MB (≈ 70 MB descompactado, ~420 mil linhas) por semestre a partir de 2022;
  csv direto até 2021 (dezenas de MB cada); `glp` ≈ 6 MB por semestre. Para 2013–2026: ~1–1,5 GB de download,
  10–40 min; tratamento ≈ 5–15 min (`fread` de ~30 arquivos, só as 5 colunas necessárias).

## Dependências

`data.table` (fread/dcast), `jsonlite`/`curl` (biblioteca comum). Zips abertos com `utils::unzip`.

## Como rodar

```
Rscript fontes/anp/01_extracao_anp.R
Rscript fontes/anp/02_tratamento_anp.R
```

## Observações metodológicas

- **Unidades das vendas:** os CSVs trazem volume em **litros** (a soma nacional de etanol hidratado em 2023,
  1,62 × 10¹⁰, corresponde aos 16,2 milhões de m³ divulgados pela ANP); o tratamento divide por 1.000 e grava m³.
  GLP vem em **kg** (P13 nacional 2023 ≈ 5,1 × 10⁹ kg) e é mantido em kg. Para asfalto e óleo combustível a
  mesma convenção (litros) foi assumida — **a confirmar** nos PDFs de metadados de cada produto; o log do
  tratamento imprime os totais nacionais do último ano para essa conferência.
- **Código IBGE nas vendas:** o CSV traz `CÓDIGO IBGE`, mas nos anos antigos parte dos códigos está fora do padrão
  (ex.: dígito verificador diferente). Usa-se o código quando existe no dicionário oficial e é coerente com a UF
  (≈ 82% das linhas do etanol); as demais são casadas por nome + UF (`juntar_por_nome_uf()` + variantes de grafia),
  elevando o casamento para ≈ 99%. Linhas sem correspondência (nomes truncados como "MONTE ALEGRE DA BA (EX",
  municípios extintos) são descartadas com log da taxa.
- **Base amostral de preços:** o Levantamento de Preços cobre um conjunto amostral de municípios/postos
  (≈ 450–600 municípios por mês), definido pela ANP; municípios não pesquisados **não** aparecem na base
  (não são zeros). Coletas com valor ausente ou zero são ignoradas. A junção é por nome em maiúsculas + sigla da UF
  (99,8% das coletas em 2024-02; a única divergência recorrente, SANTANA DO LIVRAMENTO/RS, é resolvida pela etapa de variantes).
- Nomes de produto de arquivos antigos (`OLEO DIESEL`, `ALCOOL`, `GAS NATURAL VEICULAR`) são mapeados para as mesmas
  variáveis; o layout dos CSVs de 2004–2021 é o mesmo dos atuais segundo a documentação da ANP (**a confirmar**;
  arquivos com cabeçalho diferente são ignorados com aviso no log).
