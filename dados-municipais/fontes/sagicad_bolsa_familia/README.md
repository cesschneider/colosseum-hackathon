# sagicad_bolsa_familia — Bolsa Família / Auxílio Brasil por município-mês

## Fonte

- **Órgão**: SAGI/MDS (Secretaria de Avaliação e Gestão da Informação, Ministério do Desenvolvimento e Assistência Social, Família e Combate à Fome) — **MISocial** (Matriz de Informação Social), folha de pagamento mensal do Programa Bolsa Família (PBF) e, no período de transição, do Auxílio Brasil (PAB).
- **Denominador populacional**: Ipeadata (séries municipais `POPTOT` — censos — e `ESTIMA_PO` — estimativas anuais de 1º de julho).
- **Endpoint**: `https://aplicacoes.mds.gov.br/sagi/servicos/misocial/` — consulta tipo Solr com os parâmetros `fl` (campos), `fq` (filtros), `q=*:*`, `sort`, `rows`, `start` e `wt=csv`.
  - Campos: `codigo_ibge` (IBGE **6 dígitos**), `anomes_s` (competência AAAAMM), `qtd_familias_beneficiarias_bolsa_familia`, `valor_repassado_bolsa_familia`, `pab_qtd_fam_benef_i`, `pab_valor_pago_d`.
  - Filtros: `qtd_familias_beneficiarias_bolsa_familia:* OR pab_qtd_fam_benef_i:*` e `anomes_s:[<início> TO *]`; ordenação `anomes_s asc, codigo_ibge asc`; páginas de 100.000 linhas (`rows`/`start`).
  - A competência mais recente é descoberta com a mesma consulta ordenada por `anomes_s desc` e `rows=1`.

## Indicadores

Base: `dados/tratados/sagicad_bolsa_familia/sagicad_bolsa_familia_municipal.csv` (uma linha por município-mês; chave `codigo_municipio` (7 dígitos), `nome_municipio`, `uf`, `ano`, `mes`).

| variável | descrição | unidade |
|---|---|---|
| `familias_bolsa_familia` | Famílias beneficiárias do PBF na folha do mês (ausente de nov/2021 a fev/2023) | famílias |
| `valor_bolsa_familia` | Valor total repassado pelo PBF no mês | R$ correntes |
| `familias_auxilio_brasil` | Famílias beneficiárias do Auxílio Brasil (apenas nov/2021 a fev/2023) | famílias |
| `valor_auxilio_brasil` | Valor total pago pelo Auxílio Brasil (apenas nov/2021 a fev/2023) | R$ correntes |
| `familias_beneficiarias` | Série contínua do programa vigente: PBF, ou Auxílio Brasil entre nov/2021 e fev/2023 | famílias |
| `valor_repassado` | Série contínua do valor total repassado pelo programa vigente | R$ correntes |
| `valor_medio_familia` | `valor_repassado / familias_beneficiarias` | R$ correntes por família |
| `populacao_estimada` | População residente de referência do ano (Ipeadata POPTOT/ESTIMA_PO) | habitantes |
| `familias_por_100_habitantes` | Cobertura: `100 * familias_beneficiarias / populacao_estimada` | famílias por 100 hab. |
| `valor_repassado_per_capita` | `valor_repassado / populacao_estimada` | R$ correntes por habitante |

O dicionário é gravado em `sagicad_bolsa_familia_dicionario_variaveis.csv`.

## Cobertura temporal e periodicidade

- **Mensal**, de **jan/2004** até o último mês publicado (em set/2026 a fonte ia até ago/2026; defasagem típica de ~1 mês).
- Todos os municípios do Brasil (5.560 municípios em 2004, 5.570 a partir de 2014; um código extra a partir de nov/2025 que não consta do dicionário IBGE é descartado com aviso).
- Bruto: ~1,51 milhão de linhas (município × mês).

## Tamanho estimado do download e tempo

- MISocial: ~16 páginas de 100 mil linhas; ~60–80 MB no CSV consolidado (mais as páginas preservadas em `paginas_<início>_<fim>/`); normalmente 5 a 15 minutos, dependendo da API.
- Ipeadata (`POPTOT` + `ESTIMA_PO`): ~15–20 MB de JSON, 1 a 2 minutos; gravado como `ipeadata_populacao.csv` (~6 MB).
- O script 01 reutiliza o consolidado quando a competência mais recente da fonte não mudou; quando muda, a série inteira é rebaixada (a fonte revisa meses anteriores). Versões obsoletas do mesmo início são apagadas.

## Dependências

R (≥ 4.x) com `jsonlite` e `curl` (exigidos por `00_comum`). `data.table` é opcional (acelera leitura/gravação dos CSVs grandes). Não usa 7-Zip nem pacotes de Excel.

## Como rodar

```
Rscript fontes/sagicad_bolsa_familia/01_extracao_sagicad_bolsa_familia.R
Rscript fontes/sagicad_bolsa_familia/02_tratamento_sagicad_bolsa_familia.R
```

Testes rápidos: `PAINEL_ANO_INICIAL=2020` (o filtro `anomes_s:[202001 TO *]` é aplicado já na API; o consolidado recebe o início no nome), `PAINEL_UFS="MG,ES"` (recorte feito no tratamento pelo dicionário oficial), `PAINEL_REBAIXAR=TRUE` (força novo download).

## Observações metodológicas

- **Transição Auxílio Brasil (nov/2021 a fev/2023)**: nesse intervalo a MISocial não publica os campos do Bolsa Família; o programa vigente (Auxílio Brasil) está nos campos `pab_*`. As colunas `familias_beneficiarias` e `valor_repassado` juntam os dois programas em uma série contínua (PBF prevalece se um mês tiver os dois), e as colunas por programa preservam a origem. Mudanças de desenho e de valores (piso de R$ 400 em 2022, R$ 600 a partir de ago/2022, Novo Bolsa Família em mar/2023 com R$ 600 mais adicionais por criança/gestante) produzem degraus na série de valores e no benefício médio.
- **Valores nominais**: `valor_repassado` está em reais correntes de cada mês (o original deflacionava pelo IPCA para preços de um ano-base; a aplicação pode fazê-lo com `deflator_ipca_anual()` de `00_comum`).
- **Código IBGE**: a MISocial usa 6 dígitos; a conversão para 7 dígitos usa o dicionário oficial (`codigo6_para_7`). Códigos ausentes do dicionário são descartados com aviso no log.
- **População de referência**: para cada ano usa-se o censo (`POPTOT`, quando existe: 2000, 2010, 2022) ou a estimativa anual (`ESTIMA_PO`). Anos sem dado próprio no Ipeadata (por exemplo 2007, 2023 e os meses do ano corrente antes da divulgação das estimativas, em geral no segundo semestre) recebem a população do **último ano disponível anterior**; o log do script 02 lista as substituições. Há quebra de nível entre as estimativas pré-Censo 2022 (até 2021) e as pós-Censo (2022 em diante).
- **Revisões**: a fonte pode revisar meses já publicados; por isso a série completa é rebaixada sempre que surge competência nova. A validação de cada página confere cabeçalho, competência AAAAMM válida, código presente, valores não negativos e chave município-mês única.
- Diferentemente do original (que usava apenas dezembro e uma base anual), a base aqui é **mensal**; a aplicação pode obter o recorte anual escolhendo `mes == 12`.
