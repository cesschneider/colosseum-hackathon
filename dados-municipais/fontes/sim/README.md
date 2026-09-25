# sim — Mortalidade por município de residência (SIM-DO / DATASUS)

## Fonte

Ministério da Saúde / DATASUS — Sistema de Informações sobre Mortalidade (SIM), microdados das declarações de óbito (SIM-DO), um arquivo `.dbc` por UF e ano (`DO<UF><ANO>.dbc`, organizado pela UF de ocorrência/processamento).

- Definitivos: `ftp://ftp.datasus.gov.br/dissemin/publicos/SIM/CID10/DORES/`
- Preliminares: `ftp://ftp.datasus.gov.br/dissemin/publicos/SIM/PRELIM/DORES/`
- Download e leitura dos `.dbc` via `microdatasus::fetch_datasus(year_start, year_end, uf, information_system = "SIM-DO", vars = ...)`.
- Denominador das taxas: série `ESTIMA_PO` (população estimada por município, IBGE) da API OData do Ipeadata, via `ipeadata_municipal("ESTIMA_PO")`.

## Saídas

- `dados/brutos/sim/sim_do_<UF>_<ano>.rds` (ou `..._preliminar.rds`) — um RDS por UF-ano com as colunas `CODMUNRES`, `DTOBITO`, `IDADE`, `SEXO`, `CAUSABAS` (texto, como vêm do DBC).
- `dados/brutos/sim/ipeadata_estima_po.csv` — série ESTIMA_PO.
- `dados/tratados/sim/sim_municipal.csv` — uma linha por município-ano (município de **residência**).
- `dados/tratados/sim/sim_dicionario_variaveis.csv`.

## Indicadores

| variável | descrição | unidade | regra |
|---|---|---|---|
| `obitos` | óbitos de residentes | óbitos | contagem de declarações com `CODMUNRES` válido, somando os arquivos de todas as UFs |
| `idade_media_obito` | idade média ao óbito | anos | média da idade decodificada; `NA` sem óbito com idade válida |
| `homicidios` | óbitos por agressão | óbitos | `CAUSABAS` entre X85 e Y09 |
| `homicidios_masculinos` | homicídios, sexo masculino | óbitos | X85–Y09 e `SEXO = 1` |
| `homicidios_femininos` | homicídios, sexo feminino | óbitos | X85–Y09 e `SEXO = 2` (sexo ignorado fica só no total) |
| `suicidios` | lesões autoprovocadas | óbitos | `CAUSABAS` entre X60 e X84 |
| `obitos_causas_externas` | causas externas (cap. XX) | óbitos | `CAUSABAS` entre V01 e Y98 |
| `taxa_mortalidade_100mil` | mortalidade geral | por 100 mil hab. | `1e5 * obitos / populacao` |
| `taxa_homicidios_100mil` | homicídios | por 100 mil hab. | `1e5 * homicidios / populacao` |
| `taxa_suicidios_100mil` | suicídios | por 100 mil hab. | `1e5 * suicidios / populacao` |
| `taxa_causas_externas_100mil` | causas externas | por 100 mil hab. | `1e5 * obitos_causas_externas / populacao` |
| `dados_preliminares` | origem do ano | 0/1 | 1 quando o ano vem da pasta PRELIM |

Decodificação de `IDADE` (campo de 3 dígitos com a unidade embutida): primeiro dígito 0 = minutos, 1 = horas, 2 = dias, 3 = meses (todos viram idade 0), 4 = anos (0–99), 5 = 100 anos + valor; 9 ou fora de 0–130 = ignorado (`NA`). Os intervalos CID-10 são testados pela letra e pelos dois primeiros dígitos da causa básica.

Município sem óbito registrado recebe zero nos anos em que o arquivo da sua UF existe; se o arquivo da UF não foi baixado naquele ano, a linha fica `NA`.

## Cobertura e periodicidade

- Brasil, 27 UFs, 5.570 municípios, por município de residência. Anos **2000–2024 definitivos** e **2025–2026 preliminares** (situação em setembro/2026; descoberta automática nas duas pastas do FTP, o definitivo prevalece).
- Periodicidade anual. O DATASUS publica o preliminar de um ano ao longo do ano seguinte e o definitivo cerca de 18–24 meses após o fechamento. O ano-calendário corrente, quando presente em PRELIM, é **parcial** (só os meses já processados) — use `dados_preliminares` para filtrar.
- Códigos de município do SIM têm 6 dígitos: convertidos com `codigo6_para_7()` e o dicionário oficial. Códigos de "município ignorado" (`UF0000`), exterior e residentes de UFs fora de `UFS_ATIVAS` são descartados (o script informa quantos óbitos).

## Tamanho e tempo

- Cerca de 780 arquivos `.dbc` (27 UFs × 27 anos + preliminares), de 0,1 MB (AC, RR) a ~30 MB (SP); ≈ 3,5 GB no total, baixados e descompactados em pastas temporárias pelo `microdatasus`. Os RDS ficam com ≈ 0,5 GB.
- O tempo depende do FTP do DATASUS (costuma ficar entre 2 e 5 horas para o Brasil inteiro, ~1,3 milhão de óbitos por ano). A extração é retomável: UF-ano já gravado é pulado. `ESTIMA_PO` leva 2–4 minutos (≈ 165 mil linhas).
- Tratamento: 15–30 minutos (lê cada RDS uma vez e agrega com `rowsum`).

## Dependências

- `microdatasus` (≥ 3.0.0, lê o formato DBC internamente; versões 2.x exigem também `read.dbc`). Instale com `Rscript fontes/00_comum/instalar_dependencias.R --opcionais`.
- Acesso FTP ao DATASUS (pode ser bloqueado fora do Brasil ou em redes corporativas).
- O script 02 usa apenas R base (+ `curl`/`jsonlite` da biblioteca comum).

## Como rodar

```
Rscript fontes/sim/01_extracao_sim.R
Rscript fontes/sim/02_tratamento_sim.R
```

Teste rápido por UF e ano: `PAINEL_UFS="ES" PAINEL_ANO_INICIAL=2023` (baixa só ES 2023–2026, ~4 arquivos, poucos minutos). `PAINEL_REBAIXAR=TRUE` refaz todos os downloads (inclusive `ESTIMA_PO`). Arquivos preliminares são substituídos automaticamente quando o definitivo aparece no FTP.

Se a fonte `datasus_populacao` já tiver sido tratada, o script 02 usa a sua `populacao_total` para os anos sem estimativa municipal no Ipeadata (2007, 2010, 2022 e 2023, anos de censo/contagem); caso contrário as taxas desses anos ficam `NA`.

## Observações metodológicas

- Os arquivos são organizados pela UF onde o óbito foi registrado; a agregação é por **município de residência** (`CODMUNRES`) somando os arquivos de todas as UFs. Com `PAINEL_UFS` restrito, óbitos de residentes ocorridos em outras UFs não são contados.
- `ano` é o ano de ocorrência do óbito (ano do arquivo), não a data de processamento.
- Dados preliminares são revistos: contagens e taxas de anos com `dados_preliminares = 1` mudam quando o definitivo é publicado.
- Homicídios seguem a definição de agressão da CID-10 (X85–Y09); não incluem intervenções legais (Y35–Y36) nem eventos de intenção indeterminada (Y10–Y34), que entram apenas em `obitos_causas_externas`. Séries de segurança pública (registros policiais) usam outra definição e não são diretamente comparáveis.
- A idade média usa somente óbitos com idade válida; menores de um ano entram com zero.
