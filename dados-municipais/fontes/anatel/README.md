# anatel — Acessos de Banda Larga Fixa por município (Anatel) e densidade por 100 habitantes

## Fonte

- **Órgão**: Agência Nacional de Telecomunicações (Anatel) — Dados Abertos, painel "Acessos – Banda Larga Fixa" (Serviço de Comunicação Multimídia). Página: <https://dados.gov.br/dados/conjuntos-dados/acessos---banda-larga-fixa>
- **Endpoint**: <https://www.anatel.gov.br/dadosabertos/paineis_de_dados/acessos/acessos_banda_larga_fixa.zip> — um único zip (~1,04 GB) com toda a série, atualizado mensalmente (o cabeçalho `Last-Modified` do servidor é consultado para reutilizar a cópia local).
- **População**: Ipeadata/IBGE, API OData — séries `POPTOT` (população residente dos Censos e da Contagem 2007) e `ESTIMA_PO` (estimativas de 1º de julho): `https://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='<serie>')`, recorte municipal via `ipeadata_municipal()` da biblioteca comum.

## Conteúdo do zip

Para cada faixa de anos (2007-2010, 2011-2012, …, 2021, 2022, …, ano corrente) há dois arquivos com os **mesmos registros**: `Acessos_Banda_Larga_Fixa_<anos>.csv` (formato longo: `Ano;Mês;Grupo Econômico;Empresa;CNPJ;Porte;UF;Município;Código IBGE Município;Faixa de Velocidade;[Velocidade;]Tecnologia;Meio de Acesso;[Tipo de Pessoa;Tipo de Produto;]Acessos`, ~7,6 GB no total) e `…_Colunas.csv` (formato largo, um mês por coluna `AAAA-MM`, ~1 GB no total). A equivalência foi verificada (totais por mês e por município idênticos), por isso o tratamento lê os `_Colunas`, muito mais leves. Também vêm `Densidade_Banda_Larga_Fixa.csv` (densidade por domicílios, da própria Anatel), `…_Total.csv` e `Densidades.pdf`, não utilizados. Separador `;`, UTF-8, código IBGE com 7 dígitos, célula vazia = nenhum acesso no mês.

## Indicadores (`anatel_municipal.csv`, uma linha por município-ano)

| variável | descrição | unidade |
|---|---|---|
| `acessos_banda_larga_fixa` | Acessos de banda larga fixa em serviço em dezembro (todas as prestadoras, tecnologias e tipos de cliente) | acessos |
| `acessos_media_mensal` | Média mensal do ano: soma dos meses publicados ÷ `meses_informados` | acessos |
| `meses_informados` | Meses do ano publicados pela Anatel (4 em 2007-2010; 12 desde 2011) | meses |
| `acessos_fibra` | Acessos em dezembro por fibra óptica | acessos |
| `acessos_cabo_metalico` | Acessos em dezembro por cabo metálico (xDSL e similares) | acessos |
| `acessos_cabo_coaxial` | Acessos em dezembro por cabo coaxial (cable modem/HFC) | acessos |
| `acessos_radio` | Acessos em dezembro por rádio (Wi-Fi, FWA, WiMAX…) | acessos |
| `acessos_satelite` | Acessos em dezembro por satélite | acessos |
| `acessos_outros` | Acessos em dezembro por meios híbridos/outros (categorias só existentes até 2010) | acessos |
| `populacao` | População residente do ano (POPTOT quando existe, senão ESTIMA_PO; 2023 interpolado) | habitantes |
| `densidade_banda_larga_100hab` | `100 × acessos_banda_larga_fixa / populacao` | acessos por 100 habitantes |
| `densidade_media_100hab` | `100 × acessos_media_mensal / populacao` | acessos por 100 habitantes |

Colunas de chave: `codigo_municipio` (7 dígitos), `nome_municipio`, `uf`, `ano`. A soma das seis colunas por meio de acesso é igual a `acessos_banda_larga_fixa`.

## Cobertura e periodicidade

- **Territorial**: todos os municípios do Brasil com pelo menos um acesso no ano (praticamente os 5.570 desde 2010; um município sem nenhum registro no ano não aparece naquele ano).
- **Temporal**: 2007 até o último ano com dezembro publicado. Em 2007-2010 a Anatel publicou apenas março, junho, setembro e dezembro; de 2011 em diante a série é mensal. O ano corrente (sem dezembro) é ignorado e entra automaticamente quando dezembro for publicado.
- **Periodicidade da base**: anual (posição de dezembro + média do ano). A fonte é mensal e o script pode ser adaptado para `mensal = TRUE` a partir de `total_mensal`.

## Tamanho e tempo

- Download: 1 zip de ~1,04 GB (5 a 20 minutos conforme a conexão) + duas séries do Ipeadata (~10 MB em JSON, gravadas como CSV de 2 a 6 MB). O zip só é rebaixado quando o servidor informa modificação posterior ao download local (ou com `PAINEL_REBAIXAR=TRUE`).
- Tratamento: cada `_Colunas.csv` (12 a 170 MB; ~90 mil a 1,2 milhão de linhas) é extraído para pasta temporária, lido com `data.table::fread` (só as colunas necessárias), agregado e descartado. Pico de memória em torno de 1 a 2 GB; poucos minutos no total. Base final com ~100 mil linhas.

## Dependências

- R ≥ 4.1 com `jsonlite`, `curl` (script 01) e `data.table` (script 02). Sem ferramentas externas (o zip é lido com `utils::unzip`).
- Dicionário oficial de municípios (`dados/auxiliares/dicionario_municipios.csv`), criado automaticamente pela biblioteca comum se não existir.

## Como rodar

```bash
Rscript fontes/anatel/01_extracao_anatel.R    # zip da Anatel + séries de população
Rscript fontes/anatel/02_tratamento_anatel.R  # gera dados/tratados/anatel/
```

Para um teste rápido, `PAINEL_ANO_INICIAL=2024` faz o script 02 ler apenas os arquivos que contêm anos a partir de 2024 (o zip completo ainda precisa existir).

## Observações metodológicas

- **Agregação**: soma dos acessos de todas as prestadoras, tecnologias, faixas de velocidade e tipos de cliente por município-mês. O indicador principal é a posição de dezembro (estoque de acessos em serviço), como no painel oficial da Anatel; a média mensal complementa.
- **Ausência de registro = zero**: a fonte não traz linhas (nem células) para combinações sem acessos. Assim, um município com registros no ano mas sem nenhum em dezembro recebe zero em dezembro; um município sem qualquer registro no ano fica fora daquele ano (`NA` no painel).
- **Meio de acesso**: categorias da coluna `Meio de Acesso` (Fibra, Cabo Metálico, Cabo Coaxial, Rádio, Satélite; Híbrido/Outra apenas em 2007-2010). A coluna `Tecnologia` é mais granular (FTTH, xDSL, HFC, Wi-Fi, VSAT, ETHERNET…) e não é usada.
- **População**: prioridade para `POPTOT` (Censos 2000/2010/2022 e Contagem 2007) e, nos demais anos, `ESTIMA_PO`. O Ipeadata não tem estimativa para 2023; o script preenche qualquer ano sem valor com a média simples dos anos vizinhos quando ambos existem (para 2023: Censo 2022 e estimativa 2024). Anos futuros presentes no Ipeadata (projeções) só são usados se houver dezembro publicado pela Anatel.
- **Densidade**: acessos por 100 habitantes (não confundir com a densidade por 100 domicílios divulgada pela Anatel).
