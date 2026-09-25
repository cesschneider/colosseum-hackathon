# sagicad_cadunico — Cadastro Único por município-mês

## Fonte

- **Órgão**: SAGI/MDS (Secretaria de Avaliação e Gestão da Informação, Ministério do Desenvolvimento e Assistência Social, Família e Combate à Fome) — **MISocial** (Matriz de Informação Social), extrato mensal do Cadastro Único para Programas Sociais (CadÚnico): pessoas e famílias cadastradas, por faixa de renda familiar per capita.
- **Denominador populacional**: Ipeadata (séries municipais `POPTOT` — censos — e `ESTIMA_PO` — estimativas anuais de 1º de julho).
- **Endpoint**: `https://aplicacoes.mds.gov.br/sagi/servicos/misocial/` — consulta tipo Solr com os parâmetros `fl` (campos), `fq` (filtros), `q=*:*`, `sort`, `rows`, `start` e `wt=csv`.
  - Campos: `codigo_ibge` (IBGE **6 dígitos**), `anomes_s` (competência AAAAMM), `cadun_qtd_pessoas_cadastradas_i`, `cadun_qtd_familias_cadastradas_i`, `cadun_qtde_fam_sit_extrema_pobreza_s`, `cadun_qtde_fam_sit_pobreza_s`, `cadun_qtd_familias_cadastradas_pobreza_pbf_i`, `cadun_qtd_pessoas_cadastradas_pobreza_pbf_i`, `cadun_qtd_familias_cadastradas_baixa_renda_i`, `cadun_qtd_familias_cadastradas_rfpc_ate_meio_sm_i`.
  - Filtros: `cadun_qtd_pessoas_cadastradas_i:*` e `anomes_s:[<início> TO *]`; ordenação `anomes_s asc, codigo_ibge asc`; páginas de 100.000 linhas (`rows`/`start`).
  - A competência mais recente é descoberta com a mesma consulta ordenada por `anomes_s desc` e `rows=1`.

## Indicadores

Base: `dados/tratados/sagicad_cadunico/sagicad_cadunico_municipal.csv` (uma linha por município-mês; chave `codigo_municipio` (7 dígitos), `nome_municipio`, `uf`, `ano`, `mes`).

| variável | descrição | unidade |
|---|---|---|
| `pessoas_cadastradas` | Pessoas cadastradas no CadÚnico no mês | pessoas |
| `familias_cadastradas` | Famílias cadastradas no CadÚnico no mês | famílias |
| `familias_extrema_pobreza` | Famílias com renda familiar per capita até a linha de extrema pobreza vigente | famílias |
| `familias_pobreza` | Famílias com renda per capita entre a linha de extrema pobreza e a linha de pobreza vigentes | famílias |
| `familias_ate_linha_pobreza` | Famílias com renda per capita até a linha de pobreza do Bolsa Família (= extrema pobreza + pobreza) | famílias |
| `pessoas_ate_linha_pobreza` | Pessoas com renda familiar per capita até a linha de pobreza do Bolsa Família | pessoas |
| `familias_baixa_renda` | Famílias com renda per capita entre a linha de pobreza e meio salário mínimo | famílias |
| `familias_ate_meio_salario_minimo` | Famílias com renda per capita até meio salário mínimo (= até a linha de pobreza + baixa renda) | famílias |
| `populacao_estimada` | População residente de referência do ano (Ipeadata POPTOT/ESTIMA_PO) | habitantes |
| `pct_populacao_cadastrada` | `100 * pessoas_cadastradas / populacao_estimada` (pode superar 100) | % da população |

O dicionário é gravado em `sagicad_cadunico_dicionario_variaveis.csv`.

## Cobertura temporal e periodicidade

- **Mensal**, de **ago/2012** (início da série na MISocial) até o último mês publicado (em set/2026 a fonte ia até set/2026).
- Todos os municípios do Brasil (5.565 em 2012, 5.570 a partir de mai/2015; um código extra a partir de out/2025 que não consta do dicionário IBGE é descartado com aviso).
- **abr/2025 não existe na fonte** (nenhum município): o mês fica ausente da base (não é interpolado).
- Bruto: ~0,94 milhão de linhas (município × mês).

## Tamanho estimado do download e tempo

- MISocial: ~10 páginas de 100 mil linhas; ~60–80 MB no CSV consolidado (10 campos; mais as páginas preservadas em `paginas_<início>_<fim>/`); normalmente 3 a 10 minutos.
- Ipeadata (`POPTOT` + `ESTIMA_PO`): ~15–20 MB de JSON, 1 a 2 minutos; gravado como `ipeadata_populacao.csv` (~6 MB).
- O script 01 reutiliza o consolidado quando a competência mais recente da fonte não mudou; quando muda, a série inteira é rebaixada (a fonte revisa meses anteriores). Versões obsoletas do mesmo início são apagadas.

## Dependências

R (≥ 4.x) com `jsonlite` e `curl` (exigidos por `00_comum`). `data.table` é opcional (acelera leitura/gravação dos CSVs grandes). Não usa 7-Zip nem pacotes de Excel.

## Como rodar

```
Rscript fontes/sagicad_cadunico/01_extracao_sagicad_cadunico.R
Rscript fontes/sagicad_cadunico/02_tratamento_sagicad_cadunico.R
```

Testes rápidos: `PAINEL_ANO_INICIAL=2020` (o filtro `anomes_s:[202001 TO *]` é aplicado já na API; o consolidado recebe o início no nome), `PAINEL_UFS="MG,ES"` (recorte feito no tratamento pelo dicionário oficial), `PAINEL_REBAIXAR=TRUE` (força novo download).

## Observações metodológicas

- **Linhas de renda**: as faixas (extrema pobreza, pobreza, baixa renda, meio salário mínimo) seguem os limites em reais vigentes em cada mês, que mudaram várias vezes (por exemplo R$ 70/140 em 2012, R$ 89/178 em 2018, R$ 105/210 em 2022 e R$ 109/218 a partir do Novo Bolsa Família em 2023; o salário mínimo é reajustado todo ano). Comparações ao longo do tempo devem levar isso em conta.
- **Identidades** válidas em toda a série: `familias_ate_linha_pobreza = familias_extrema_pobreza + familias_pobreza` e `familias_ate_meio_salario_minimo = familias_ate_linha_pobreza + familias_baixa_renda`.
- **Parcela da população cadastrada**: razão entre um estoque cadastral (que inclui cadastros desatualizados) e uma estimativa populacional com outra data de referência; valores acima de 100% ocorrem em municípios pequenos e são mantidos sem truncamento (regra herdada do original).
- **Código IBGE**: a MISocial usa 6 dígitos; a conversão para 7 dígitos usa o dicionário oficial (`codigo6_para_7`). Códigos ausentes do dicionário são descartados com aviso no log.
- **População de referência**: para cada ano usa-se o censo (`POPTOT`, quando existe: 2010, 2022) ou a estimativa anual (`ESTIMA_PO`). Anos sem dado próprio no Ipeadata (por exemplo 2023 e os meses do ano corrente antes da divulgação das estimativas, em geral no segundo semestre) recebem a população do **último ano disponível anterior** (o que reproduz a regra "2023 = ano anterior" do original); o log do script 02 lista as substituições. Há quebra de nível entre as estimativas pré-Censo 2022 (até 2021) e as pós-Censo (2022 em diante).
- **Revisões**: a fonte pode revisar meses já publicados; por isso a série completa é rebaixada sempre que surge competência nova. A validação de cada página confere cabeçalho, competência AAAAMM válida, código presente, valores não negativos e chave município-mês única.
- Diferentemente do original (que usava apenas dezembro, base anual e um único indicador de proporção), a base aqui é **mensal** e traz os estoques por faixa de renda; a aplicação pode obter o recorte anual escolhendo `mes == 12`.
