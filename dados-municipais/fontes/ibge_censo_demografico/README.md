# IBGE – Censos Demográficos 2000, 2010 e 2022 (`ibge_censo_demografico`)

## Fonte

- **Órgão:** IBGE, Diretoria de Pesquisas, Censos Demográficos.
- **Conjuntos:** população residente por sexo e grupos de idade, tabelas SIDRA **1552** (Censos 2000 e 2010) e **9514** (Censo 2022), variável 93 (população residente, pessoas).
- **Páginas:** https://sidra.ibge.gov.br/tabela/1552 e https://sidra.ibge.gov.br/tabela/9514

## Endpoints

Seis consultas (por ano censitário, uma por idade e uma por sexo), cada uma feita UF a UF pela biblioteca comum:

| tabela / ano | consulta | caminho da API SIDRA (`https://apisidra.ibge.gov.br/values` + …) |
|---|---|---|
| 1552 / 2000 e 2010 | idade (sexo total) | `/t/1552/n6/in%20n3%20<cod_uf>/v/93/p/<ano>/c1/0/c2/0/c286/0/c287/93070,93084,…,93100,6653` |
| 1552 / 2000 e 2010 | sexo (idade total) | `/t/1552/n6/in%20n3%20<cod_uf>/v/93/p/<ano>/c1/0/c2/92956,92957/c286/0/c287/0` |
| 9514 / 2022 | idade (sexo total) | `/t/9514/n6/in%20n3%20<cod_uf>/v/93/p/2022/c2/6794/c287/93070,93084,…,93098,49108,49109,60040,60041,6653/c286/113635` |
| 9514 / 2022 | sexo (idade total) | `/t/9514/n6/in%20n3%20<cod_uf>/v/93/p/2022/c2/4,5/c287/100362/c286/113635` |

Classificações: `c1` situação do domicílio, `c2` sexo, `c286` forma de declaração da idade, `c287` grupos de idade. Os códigos de categoria diferem entre as tabelas (sexo: 92956/92957 na 1552, 4/5 na 9514; totais: 0 na 1552, 6794/100362/113635 na 9514) e os grupos finais de idade também: a 1552 publica 80–89 (93099) e 90–99 (93100), enquanto a 9514 publica 80–84 (49108), 85–89 (49109), 90–94 (60040) e 95–99 (60041); ambas têm 100 ou mais (6653). O script 02 faz esse mapeamento.

## Indicadores (`ibge_censo_demografico_municipal.csv`)

Uma linha por município-ano (anos 2000, 2010 e 2022). Chaves: `codigo_municipio` (7 dígitos), `nome_municipio`, `uf`, `ano`.

| variável | descrição | unidade |
|---|---|---|
| `populacao_total` | População residente (homens + mulheres) | pessoas |
| `pop_homens` | População residente masculina | pessoas |
| `pop_mulheres` | População residente feminina | pessoas |
| `pop_0_a_4` | População de 0 a 4 anos | pessoas |
| `pop_5_a_9` | População de 5 a 9 anos | pessoas |
| `pop_10_a_19` | População de 10 a 19 anos | pessoas |
| `pop_20_a_29` | População de 20 a 29 anos | pessoas |
| `pop_30_a_39` | População de 30 a 39 anos | pessoas |
| `pop_40_a_49` | População de 40 a 49 anos | pessoas |
| `pop_50_a_59` | População de 50 a 59 anos | pessoas |
| `pop_60_mais` | População de 60 anos ou mais | pessoas |
| `pop_0_a_14` | População de 0 a 14 anos | pessoas |
| `pop_15_a_64` | População de 15 a 64 anos | pessoas |
| `pop_65_mais` | População de 65 anos ou mais | pessoas |
| `razao_dependencia_jovem` | `pop_0_a_14 / pop_15_a_64 × 100` | por 100 |
| `razao_dependencia_idosa` | `pop_65_mais / pop_15_a_64 × 100` | por 100 |
| `razao_dependencia_total` | `(pop_0_a_14 + pop_65_mais) / pop_15_a_64 × 100` | por 100 |
| `indice_envelhecimento` | `pop_65_mais / pop_0_a_14 × 100` | por 100 |
| `razao_sexo` | `pop_homens / pop_mulheres × 100` | por 100 |

As oito faixas etárias (`pop_0_a_4` … `pop_60_mais`) e os totais por sexo reproduzem a estrutura original do painel; os grandes grupos e as razões seguem as definições usuais do IBGE (corte em 15 e 65 anos).

## Cobertura temporal e periodicidade

- **Anos:** 2000, 2010 e 2022 (decenal). O próximo Censo deve exigir nova tabela SIDRA e, provavelmente, novos códigos de categoria.
- **Municípios:** todos os 5.570 no Censo 2022. Em 2000 e 2010 faltam os municípios instalados depois do respectivo Censo (por exemplo, Governador Lindenberg/ES em 2000 e os cinco municípios criados em 2013 em 2010); essas linhas ficam sem nenhum valor na API e são descartadas.

## Tamanho e tempo estimados

- 6 consultas × 27 UFs = 162 requisições; ~360 mil linhas no total (cerca de 160 MB de JSON transferidos); brutos gravados em seis arquivos RDS comprimidos (~5 MB no total).
- Tempo total típico: 2 a 4 minutos.

## Dependências

R base + `jsonlite` + `curl` (biblioteca comum). `data.table` é opcional.

## Como rodar

```bash
Rscript fontes/ibge_censo_demografico/01_extracao_ibge_censo_demografico.R
Rscript fontes/ibge_censo_demografico/02_tratamento_ibge_censo_demografico.R
```

Saídas:

- `dados/brutos/ibge_censo_demografico/sidra_<tabela>_<ano>_<idade|sexo>.rds` – retorno da API tal como recebido (valores em texto), mais `sidra_censo_assinatura.txt` (UFs da coleta);
- `dados/tratados/ibge_censo_demografico/ibge_censo_demografico_municipal.csv` e `ibge_censo_demografico_dicionario_variaveis.csv`.

Reutilização: dados censitários não mudam, então os brutos existentes são reaproveitados (exceto se foram coletados com outro conjunto de UFs ativas). `PAINEL_REBAIXAR=TRUE` força nova coleta; `PAINEL_UFS=AC` serve para testes.

## Observações metodológicas

- Símbolos do SIDRA: `-` é zero absoluto e vira `0`; `...`, `..` e `X` (indisponível/não se aplica/omitido) viram `NA`. A soma de uma faixa etária só é calculada com os componentes disponíveis e fica `NA` quando todos estão indisponíveis; indisponibilidade nunca é tratada como população zero.
- O script exige que cada município-ano traga todas as categorias de idade da tabela (19 na 1552, 21 na 9514); caso contrário, interrompe, para não subestimar as faixas.
- A soma das oito faixas etárias deve coincidir com `populacao_total` (homens + mulheres); divergências são apenas registradas no log (nas tabelas atuais não há divergência).
- Razões são `NA` quando o denominador é zero ou indisponível.
- A população de 2000/2010 corresponde à malha municipal vigente na tabela SIDRA (divisão territorial atual do IBGE), não à malha da época.
