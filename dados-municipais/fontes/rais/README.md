# RAIS – Relação Anual de Informações Sociais (MTE/PDET)

Microdados públicos identificados por município da RAIS, divulgados pelo Ministério do Trabalho e Emprego (Programa de Disseminação das Estatísticas do Trabalho – PDET). A fonte cobre o mercado de trabalho formal: estabelecimentos e vínculos empregatícios celetistas e estatutários, com posição em 31 de dezembro do ano-base.

- **Endpoint (primário):** `ftp://ftp.mtps.gov.br/pdet/microdados/RAIS/<ano>/`
- **Espelho (fallback opcional):** `https://huggingface.co/datasets/selenelindsay/rais-caged-bronze` (pasta `RAIS/<ano>/`; em 24/09/2026 contém apenas o ano-base 2025). Desative com `PAINEL_RAIS_ESPELHO=FALSE`.
- **Layouts oficiais (xls):** `ftp://ftp.mtps.gov.br/pdet/microdados/RAIS/Layouts/`
- **Saídas:** `dados/brutos/rais/<ano>/*.7z` (originais), `dados/brutos/rais/parciais/rais_<ano>.csv` (agregado anual, para retomada), `dados/tratados/rais/rais_municipal.csv` e `rais_dicionario_variaveis.csv`.

## Indicadores (`rais_municipal.csv`, uma linha por município-ano)

| variável | descrição | unidade | regra de cálculo |
|---|---|---|---|
| `estabelecimentos` | Estabelecimentos com atividade no ano e declaração positiva | estabelecimentos | contagem no arquivo de estabelecimentos com `Ind Atividade Ano = 1` e `Ind RAIS Negativa = 0` |
| `vinculos_ativos` | Vínculos empregatícios ativos em 31/12 | vínculos | contagem no arquivo de vínculos com `Vínculo Ativo 31/12 = 1`; nos layouts que trazem a marca `Vínculo Abandonado`, exige `= 0` |
| `vinculos_com_remuneracao` | Vínculos ativos com remuneração de dezembro informada | vínculos | contagem dos vínculos ativos cujo `Vl Remun Dezembro Nom` não está vazio (denominador da média) |
| `massa_salarial_dez` | Massa salarial nominal de dezembro | R$ correntes | soma de `Vl Remun Dezembro Nom` dos vínculos ativos |
| `remuneracao_media_dez` | Remuneração média nominal de dezembro | R$ correntes | `massa_salarial_dez / vinculos_com_remuneracao` (NA quando o denominador é zero) |
| `taxa_ocupacao` | Vínculos ativos por habitante | razão | `vinculos_ativos / população residente estimada` (Ipeadata, série `ESTIMA_PO`, IBGE); NA quando não há população para o ano |
| `<indicador>_<setor>` | Abertura setorial dos cinco primeiros indicadores | idem | setor pelo código `IBGE Subsetor` do estabelecimento: `industria` (1–14), `construcao_civil` (15), `comercio` (16–17), `servicos` (18–24), `agropecuaria` (25), `nao_classificado` (demais/ignorado) |
| `massa_salarial_dez_reais_<ano>`, `remuneracao_media_dez_reais_<ano>` | Opcionais: valores em reais de um ano-base | R$ de `<ano>` | só quando `PAINEL_RAIS_ANO_BASE_REAIS=<ano>`; usa `deflator_ipca_anual()` (IPCA médio anual, SGS 433) |

Os totais são a soma dos seis setores. Município presente no arquivo do ano sem registro em algum setor recebe zero nesse setor (zero real); município ausente de um arquivo fica `NA` naquele bloco de indicadores. Valores monetários ficam **nominais** (a aplicação deflaciona quando quiser).

## Cobertura e periodicidade

- **Territorial:** todos os municípios do Brasil (código IBGE de 6 dígitos da RAIS convertido para 7 dígitos pelo dicionário oficial). Registros com município ignorado ou inexistente no dicionário são descartados.
- **Temporal:** padrão de **2010 até o último ano-base publicado** (2025 em 24/09/2026; o FTP tem pastas de 1985 a 2025). Altere `ANO_INICIAL` nos dois scripts para recuar (anos anteriores a 2010 usam o mesmo layout por UF, mas não foram testados).
- **Periodicidade:** anual; posição em 31/12 do ano-base, publicada no ano seguinte. O MTE às vezes republica um ano (ex.: RAIS 2024 teve um segundo processamento em 18/05/2026, incorporando a administração pública); como a reutilização compara o tamanho local com o do FTP, a republicação é rebaixada automaticamente.

## Arquivos e tamanho estimado dos downloads

| ano-base | arquivos | tamanho compactado |
|---|---|---|
| 2010–2017 | `<UF><ano>.7z` (27 arquivos de vínculos, um por UF) + `ESTB<ano>.7z` (estabelecimentos) | 1,5 GB (2010) a 2,7 GB (2016) por ano |
| 2018–2025 | `RAIS_VINC_PUB_{CENTRO_OESTE, MG_ES_RJ, NORDESTE, NORTE, SP, SUL}.7z` + `RAIS_ESTAB_PUB.7z` | 2,6 GB (2020) a 3,9 GB (2025) por ano; o de SP sozinho chega a 1,1 GB |

Total aproximado para 2010–2025, Brasil inteiro: **43 GB** compactados (os .7z ficam guardados; nada é descompactado em disco). Tempo de download depende do FTP do MTE: ~2,5 h a 5 MB/s, ~12 h a 1 MB/s. O tratamento lê tudo em fluxo: estime 15–45 min por ano-base para o Brasil inteiro (o gargalo é descompactar e analisar ~80 milhões de linhas de vínculos por ano), ou seja, algumas horas para a série completa; com `PAINEL_UFS="MG,ES"` e um único ano leva minutos.

Arquivos não baixados: `RAIS_VINC_PUB_NI.7z` (vínculos com UF não identificada, sem município), as pastas `2023 Parcial`/`2024 Parcial` e as subpastas com a versão anterior dos arquivos de 2019 e 2023.

## Dependências

- **R** com `curl`, `jsonlite` e **`data.table`** (instale com `fontes/00_comum/instalar_dependencias.R`).
- **7-Zip** (linha de comando): procurado em `PAINEL_7Z`, no PATH (`7z`, `7za`, `7zr`) e em `C:/Program Files/7-Zip/`. Baixe em <https://www.7-zip.org/download.html> – o `7zr.exe` (versão reduzida) é suficiente. O único `.zip` da série (estabelecimentos de 2002) é lido pelo próprio R.
- Acesso a `ftp.mtps.gov.br` (porta 21) e a `www.ipeadata.gov.br` (população para a taxa de ocupação; se indisponível, a coluna fica vazia e o script segue).

## Como rodar

```bash
Rscript fontes/00_comum/01_dicionario_municipios.R   # uma vez
Rscript fontes/rais/01_extracao_rais.R               # baixa e valida (7z t) os .7z
Rscript fontes/rais/02_tratamento_rais.R             # lê em fluxo, agrega e grava a base
```

Teste rápido por UF e ano (baixa só as regiões/UFs necessárias e processa só o pedido):

```bash
PAINEL_UFS="MG,ES" PAINEL_ANO_INICIAL=2024 Rscript fontes/rais/01_extracao_rais.R
PAINEL_UFS="MG,ES" PAINEL_ANO_INICIAL=2024 Rscript fontes/rais/02_tratamento_rais.R
```

Variáveis de ambiente específicas: `PAINEL_7Z` (caminho do executável), `PAINEL_RAIS_ANO_FINAL` (limita o último ano), `PAINEL_RAIS_ESPELHO=FALSE` (sem fallback), `PAINEL_RAIS_BLOCO` (linhas por bloco de leitura; padrão 500000, reduza se faltar memória), `PAINEL_RAIS_REPROCESSAR=TRUE` (ignora as parciais em `dados/brutos/rais/parciais/`), `PAINEL_RAIS_ANO_BASE_REAIS=2024` (colunas deflacionadas). As parciais recebem o sufixo das UFs quando `PAINEL_UFS` está definido, para não misturar um teste com a rodada nacional. Também valem as variáveis gerais (`PAINEL_REBAIXAR`, `PAINEL_DADOS`, `PAINEL_TIMEOUT`).

## Observações metodológicas

- **Vínculo ativo em 31/12**: estoque de empregos formais no fim do ano, não o total de vínculos do ano (o arquivo traz também os desligados). A marca de vínculo abandonado só existe nos layouts recentes; nos demais anos nenhum vínculo é excluído por esse critério.
- **Estabelecimentos**: contam-se os com atividade no ano e declaração positiva (excluem-se as "RAIS negativas", sem empregados). Corresponde ao critério das tabulações oficiais.
- **Remuneração de dezembro**: massa e média usam `Vl Remun Dezembro Nom` (nominal). O denominador da média é o número de vínculos ativos com o campo informado, inclusive valores zero; a média das tabulações do PDET pode diferir por excluir remunerações zeradas.
- **Município** é o do estabelecimento (`Município`/`Município - Código`), não o de trabalho (`Mun Trab`), seguindo as tabulações oficiais.
- **Mudanças de layout entre anos**: até 2017 os arquivos são por UF e o cabeçalho traz `Município`, `IBGE Subsetor`, `Vínculo Ativo 31/12`, `Vl Remun Dezembro Nom`, `Ind Atividade Ano`, `Ind Rais Negativa`; de 2018 em diante os vínculos vêm por região; nas republicações mais recentes (2024/2025) os nomes ganham o sufixo ` - Código` (ex.: `Município - Código`, `IBGE Subsetor - Código`) e surge a coluna `Vínculo Abandonado`. O script casa os nomes por padrão normalizado (sem acento/pontuação) e para com o cabeçalho completo na mensagem se alguma coluna não for encontrada.
- **Encoding e separadores**: arquivos em Latin-1 (UTF-8 é detectado pelo cabeçalho), separador `;`, decimal `,`. A leitura é em blocos a partir do stdout do 7-Zip, sem gravar o arquivo descompactado (o de vínculos de SP passa de 10 GB aberto).
- **Comparabilidade**: a RAIS 2024 publicada até maio de 2026 (primeiro processamento) não trazia a administração pública; o FTP hoje traz o segundo processamento. Se o seu bruto de 2024 for anterior a 18/05/2026, rode o script 01 de novo (o tamanho diferente força o novo download) e depois `PAINEL_RAIS_REPROCESSAR=TRUE` no script 02.
- **População** (taxa de ocupação): estimativas do IBGE via Ipeadata (`ESTIMA_PO`, 1º de julho); em anos censitários a série pode não cobrir todos os municípios, e a taxa fica `NA` onde não há população.
