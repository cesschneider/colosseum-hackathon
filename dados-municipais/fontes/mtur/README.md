# mtur — Cadastur: meios de hospedagem e guias de turismo (Ministério do Turismo)

## Fonte

- **Órgão**: Ministério do Turismo (MTur), sistema Cadastur (cadastro obrigatório de prestadores de serviços turísticos), publicado no portal de Dados Abertos.
- **Página principal**: https://dados.turismo.gov.br/
- **Descoberta (API CKAN, `package_show`)**:
  - Meios de hospedagem: `https://dados.turismo.gov.br/api/3/action/package_show?id=meios-de-hospedagem`
  - Guias de turismo: `https://dados.turismo.gov.br/api/3/action/package_show?id=prestadores-de-servicos-turisticos-guia-turismo_2`
- Cada dataset lista um recurso por ano (2006–2015) ou por trimestre (2016 em diante), em **CSV** (até 2022), **XLS** (2023 e 1º semestre de 2024) e **XLSX** (desde o 3º trimestre de 2024). O script 01 escolhe, para cada ano, o recurso anual ou o trimestre mais recente publicado (retrato do cadastro no fim do ano; no ano corrente, o último trimestre disponível). Recursos repetidos do mesmo período: vale o de modificação mais recente.
- Arquivos brutos: `dados/brutos/mtur/mtur_<hospedagem|guias>_<ANO>_<anual|t1..t4>.<csv|xls|xlsx>`.

## Indicadores (`dados/tratados/mtur/mtur_municipal.csv`, município-ano)

| variável | descrição | unidade |
|---|---|---|
| `n_meios_hospedagem` | Meios de hospedagem cadastrados no município (CNPJ distintos no retrato do ano) | estabelecimentos |
| `n_leitos` | Total de leitos dos meios de hospedagem cadastrados (soma) | leitos |
| `n_unidades_habitacionais` | Total de unidades habitacionais (quartos/apartamentos) dos meios de hospedagem cadastrados (soma) | unidades habitacionais |
| `n_guias_turismo` | Guias de turismo cadastrados no município (pessoas distintas: CPF, certificado ou nome) | guias |

## Cobertura e periodicidade

- **Territorial**: todos os municípios do Brasil. O Cadastur **não traz o código IBGE**; o município é casado por nome normalizado + UF com o dicionário oficial (`juntar_por_nome_uf()`). Nomes com grafia divergente ficam fora da base (a taxa de casamento e exemplos aparecem no log).
- **Temporal**: 2006 até o ano corrente (um retrato por ano). O "ano" é o ano do retrato do cadastro (arquivo anual ou último trimestre publicado), não a data de cadastro do prestador.
- **Periodicidade**: anual.

## Tamanho e tempo estimados

- 42 arquivos (21 anos × 2 datasets), de 0,2 MB a 12 MB cada: **cerca de 200 MB** no total.
- O portal é lento em alguns horários (os XLSX recentes de 5–12 MB podem levar vários minutos cada); estime **20 a 60 min** para a primeira coleta. Execuções seguintes reutilizam os anos encerrados e rebaixam apenas o ano corrente.
- Tratamento: leitura de CSV/XLS/XLSX com `data.table` e `readxl`, ~3 a 10 min.

## Dependências

- R ≥ 4.1 com `jsonlite` e `curl` (biblioteca comum), `data.table` (recomendado ≥ 1.16, para `fill = Inf` nos CSVs históricos com campos a mais) e `readxl` (XLS e XLSX).
- Nenhum pacote é instalado pelos scripts (`fontes/00_comum/instalar_dependencias.R`).

## Como rodar

```
Rscript fontes/mtur/01_extracao_mtur.R     # consulta o CKAN e baixa/reutiliza os brutos
Rscript fontes/mtur/02_tratamento_mtur.R   # gera dados/tratados/mtur/mtur_municipal.csv
```

Variáveis úteis para testes: `PAINEL_ANO_INICIAL=2024`, `PAINEL_REBAIXAR=TRUE`, `PAINEL_DADOS=<pasta>`.

## Observações metodológicas

- **Layouts que mudam**: os nomes de colunas variam entre anos (`LOCALIDADE`/`Município`, `CNPJ`/`Número de Inscrição do CNPJ`, `UH`/`Unidade Habitacionais`, `TOTAL DE LEITOS`/`Leitos`, `NOME`/`Nome Completo`/`CPF`/`Número do Certificado`). O script normaliza os nomes (minúsculas, sem acento, `_`) e procura cada campo em uma lista de alternativas.
- **CSVs históricos**: codificação Windows-1252/Latin-1 (detecta-se UTF-8 quando válido), quebras de linha CRLF, LF ou apenas CR, campos ora entre aspas ora sem aspas, aspas avulsas e linhas com campos a mais (deslocados). O texto é normalizado antes da leitura; nas linhas deslocadas, valores não numéricos em leitos/UH viram `NA` e não entram na soma.
- **Guias PF e PJ**: desde 2024 o arquivo de guias traz abas separadas para pessoa física e pessoa jurídica; as duas são empilhadas e o guia é deduplicado por CPF/CNPJ (só dígitos), certificado ou nome. O script interrompe se alguma das abas não for identificada.
- **Duplicidades**: meios de hospedagem contam CNPJ distintos; linhas sem CNPJ contam como estabelecimentos separados. Leitos e unidades habitacionais são somados linha a linha, como no cálculo original.
- **Situação cadastral**: não há filtro por situação (regular, em análise, etc.) — conta-se tudo o que consta no retrato, como no cálculo original. Mudanças de regras e de estrutura da publicação da fonte (por exemplo, republicações de 2024) podem produzir quebras na série; compare anos com cautela.
- **Zeros**: município presente no cadastro de hospedagem e ausente no de guias (ou vice-versa) recebe `0` no indicador ausente, porque o cadastro é exaustivo. Municípios ausentes nos dois cadastros em um ano não aparecem naquele ano. O script exige que cada ano tenha os dois retratos antes de atribuir zeros.
