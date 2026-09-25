# Inep — Censo Escolar, Taxas de Rendimento, Ideb, Enem e Censo da Educação Superior

Fonte: **Inep** (Instituto Nacional de Estudos e Pesquisas Educacionais Anísio Teixeira), dados abertos do portal gov.br. Cinco fluxos independentes, todos agregados por **município-ano para todo o Brasil**.

| Fluxo (`PAINEL_INEP_FLUXOS`) | Página de descoberta | O que é baixado | Base tratada |
|---|---|---|---|
| `censo_escolar` | https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/censo-escolar | `microdados_censo_escolar_<ano>.zip` (um por ano) | `inep_censo_escolar_municipal.csv` |
| `taxas_rendimento` | https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/indicadores-educacionais/taxas-de-rendimento-escolar | aba de cada ano → ZIP rotulado "Municípios" | `inep_rendimento_municipal.csv` |
| `ideb_municipios` | https://www.gov.br/inep/pt-br/areas-de-atuacao/pesquisas-estatisticas-e-indicadores/ideb/resultados | 3 ZIPs municipais (anos iniciais, anos finais, ensino médio) da edição mais recente | `inep_ideb_municipal.csv` |
| `enem` | https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/enem | `microdados_enem_<ano>.zip` (um por ano; os "Complemento… Redação" são ignorados) | `inep_enem_municipal.csv` |
| `censo_superior` | https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/censo-da-educacao-superior | `microdados_censo_da_educacao_superior_<ano>.zip` | `inep_educacao_superior_municipal.csv` |

Os links **não são fixos no código**: o script 01 lê as páginas acima (âncoras `Microdados do … <ano>`, abas `data-url` por ano nas taxas, aba "2005 | 2025" do Ideb) e extrai o ano do nome do arquivo. Os arquivos ficam em `dados/brutos/inep/<fluxo>/<fluxo>[_<etapa>]_<ano>.zip` e o plano de coleta em `dados/brutos/inep/links_descobertos.csv`.

## Indicadores

Todas as bases têm as colunas `codigo_municipio` (7 dígitos, texto), `nome_municipio`, `uf` (do dicionário oficial IBGE) e `ano`. Os indicadores abaixo estão no dicionário único `inep_dicionario_variaveis.csv` (coluna `tabela` = nome da base).

### `inep_censo_escolar_municipal` (Censo Escolar, arquivo escola-nível)

| variável | descrição | unidade | regra de cálculo |
|---|---|---|---|
| `num_matriculas_ensino_basico` | matrículas na educação básica | matrículas | soma de `QT_MAT_BAS` das escolas do município |
| `num_matriculas_ensino_fundamental` | matrículas no ensino fundamental | matrículas | soma de `QT_MAT_FUND` |
| `num_matriculas_ensino_medio` | matrículas no ensino médio | matrículas | soma de `QT_MAT_MED` |
| `num_escolas_ensino_basico` | escolas com matrícula na educação básica | escolas | `CO_ENTIDADE` distintos com `QT_MAT_BAS > 0` |
| `num_escolas_ensino_fundamental` | escolas com matrícula no fundamental | escolas | distintos com `QT_MAT_FUND > 0` |
| `num_escolas_ensino_medio` | escolas com matrícula no médio | escolas | distintos com `QT_MAT_MED > 0` |
| `num_salas_aula` | salas de aula utilizadas | salas | soma de `QT_SALAS_UTILIZADAS` |
| `num_professores` | docentes da educação básica | docentes | soma de `QT_DOC_BAS` por escola (**sem** somar `QT_DOC_INF + QT_DOC_FUND + QT_DOC_MED`) |

### `inep_rendimento_municipal` (Taxas de Rendimento Escolar, planilha municipal)

| variável | descrição | unidade | regra de cálculo |
|---|---|---|---|
| `taxa_aprovacao_ensino_fundamental` | taxa de aprovação, ensino fundamental | % (0–100) | linha do município com Localização = Total e Rede = Total; coluna `1_CAT_FUN` (layout recente) ou "Total Aprovação no Ens. Fundamental" (layout histórico) |
| `taxa_aprovacao_ensino_medio` | taxa de aprovação, ensino médio | % (0–100) | idem, `1_CAT_MED` |
| `taxa_reprovacao_ensino_fundamental` | taxa de reprovação, ensino fundamental | % (0–100) | idem, `2_CAT_FUN` |
| `taxa_reprovacao_ensino_medio` | taxa de reprovação, ensino médio | % (0–100) | idem, `2_CAT_MED` |
| `taxa_abandono_ensino_fundamental` | taxa de abandono, ensino fundamental | % (0–100) | idem, `3_CAT_FUN` |
| `taxa_abandono_ensino_medio` | taxa de abandono, ensino médio | % (0–100) | idem, `3_CAT_MED` |

### `inep_ideb_municipal` (Ideb, planilhas municipais)

| variável | descrição | unidade | regra de cálculo |
|---|---|---|---|
| `ideb_nota_anos_iniciais` | Ideb observado, anos iniciais do fundamental | nota (0–10) | linha do município com `REDE = Pública`, coluna `VL_OBSERVADO_<ano>` |
| `ideb_nota_anos_finais` | Ideb observado, anos finais do fundamental | nota (0–10) | idem |
| `ideb_nota_ensino_medio` | Ideb observado, ensino médio | nota (0–10) | idem |

### `inep_enem_municipal` (microdados do Enem, município da escola)

| variável | descrição | unidade | regra de cálculo |
|---|---|---|---|
| `enem_num_individuos_prova_completa` | participantes com prova completa | participantes | participantes com as cinco notas não ausentes e `CO_MUNICIPIO_ESC` informado |
| `enem_nota_ciencias_natureza` | nota média em ciências da natureza | pontos (0–1000) | média de `NU_NOTA_CN` desses participantes |
| `enem_nota_ciencias_humanas` | nota média em ciências humanas | pontos | média de `NU_NOTA_CH` |
| `enem_nota_linguagens` | nota média em linguagens e códigos | pontos | média de `NU_NOTA_LC` |
| `enem_nota_matematica` | nota média em matemática | pontos | média de `NU_NOTA_MT` |
| `enem_nota_redacao` | nota média da redação | pontos | média de `NU_NOTA_REDACAO` |
| `enem_nota_media` | nota média geral | pontos | média simples das cinco notas de cada participante, depois média municipal |

### `inep_educacao_superior_municipal` (Censo da Educação Superior)

| variável | descrição | unidade | regra de cálculo |
|---|---|---|---|
| `ens_superior_num_instituicoes` | IES com sede no município | instituições | `CO_IES` distintos pelo `CO_MUNICIPIO_IES` |
| `ens_superior_num_docentes` | docentes em exercício | docentes | soma de `QT_DOC_EXE` por IES (`QT_DOCENTE_EXE` em 2009; `QT_DOC_TOTAL` só na falta) |
| `ens_superior_num_matriculas` | matrículas em cursos de graduação | matrículas | soma de `QT_MAT` (ou alias) pelo município do curso; sede da IES quando o curso não informa município |

## Cobertura temporal e periodicidade

| Fluxo | Cobertura | Periodicidade | Observação |
|---|---|---|---|
| Censo Escolar | 2007 → mais recente (2025 já publicado) | anual | portal oferece desde 1995, mas o layout escola-nível comparável começa em 2007 |
| Taxas de rendimento | 2007 → 2025 | anual | uma aba por ano no portal |
| Ideb | 2005 → 2025 (bienal: 2005, 2007, …, 2025) | bienal | a planilha da edição mais recente traz `VL_OBSERVADO_` de todas as edições; só ela é baixada |
| Enem | 2009 → 2025 | anual | as quatro provas por área existem só no "novo Enem" (2009+) |
| Censo Superior | 2009 → 2024 | anual | reformulado em 2009 (coleta individual de alunos e docentes) |

`PAINEL_ANO_INICIAL` limita os anos (nunca abaixo do início de cada série); `PAINEL_UFS` limita as UFs (filtro por `SG_UF`/código IBGE) — ambos apenas para testes.

## Tamanho dos downloads e tempo estimado

| Fluxo | Arquivos | Tamanho dos ZIPs | Descompactado (temporário) |
|---|---|---|---|
| Censo Escolar | 19 (2007–2025) | ~25–32 MB por ano até 2024; **512 MB em 2025** (tabelas separadas, sem compressão) | ~200 MB por ano (CSV único); 2025: ~340 MB nas três tabelas usadas |
| Taxas de rendimento | 19 | 1–3 MB cada | planilha xls/xlsx |
| Ideb | 3 | ~30 MB no total | 3 planilhas xlsx (~12 MB cada) |
| Enem | 17 (2009–2025) | **~500 MB a 1 GB por ano** (≈ 10 GB no total) | **1,6 a 4 GB por ano** (`MICRODADOS_ENEM_<ano>.csv`; a partir de 2024 `RESULTADOS_` + `PARTICIPANTES_`) |
| Censo Superior | 16 (2009–2024) | 4–40 MB por ano; **435 MB em 2024** | 30–430 MB (cadastro de cursos) |

Total aproximado: **~12 GB de ZIPs** e picos de **4 GB de espaço temporário** (Enem 2009). Tempo: o download completo leva de 1 a várias horas conforme a conexão (o servidor `download.inep.gov.br` reinicia conexões com alguma frequência; `baixar_arquivo` tenta 3 vezes e reutiliza ZIPs já válidos). O tratamento do Enem é o mais lento (descompactar + ler ~4 milhões de linhas por edição): estime 2–6 min por ano; Censo Escolar ~30 s por ano; demais fluxos segundos. Uma execução nacional completa fica entre 1 e 3 horas depois dos downloads.

Os brutos são reutilizados entre execuções (`PAINEL_REBAIXAR=TRUE` força novo download). O tratamento grava **parciais por edição** em `dados/brutos/inep/parciais/<recorte>/<fluxo>_<ano>.csv` (`<recorte>` = `brasil` ou as UFs de teste): se a execução for interrompida, a próxima retoma de onde parou; `PAINEL_INEP_REPROCESSAR=TRUE` refaz tudo.

## Dependências

- R ≥ 4.1 com `jsonlite`, `curl` (biblioteca comum), `data.table` e `readxl` (xls e xlsx das taxas e do Ideb).
- Sem pacotes extras para descompactar: usa `utils::unzip`; para membros zip64 (> 4 GB, ex.: Enem 2009) recorre ao `tar` do Windows ou ao `unzip` do sistema, se necessário.
- Espaço em disco: ~12 GB para os brutos + até 4 GB temporários (`PAINEL_INEP_TEMP` define a pasta; padrão `tempdir()`).

## Como rodar

```bash
Rscript fontes/inep/01_extracao_inep.R          # descobre links, baixa e valida os ZIPs
Rscript fontes/inep/02_tratamento_inep.R        # agrega e grava as 5 bases + dicionário

# só alguns fluxos (mesma variável nos dois scripts)
PAINEL_INEP_FLUXOS="ideb_municipios,taxas_rendimento" Rscript fontes/inep/01_extracao_inep.R
PAINEL_INEP_FLUXOS="ideb_municipios,taxas_rendimento" Rscript fontes/inep/02_tratamento_inep.R

# só listar os links descobertos, sem baixar
PAINEL_INEP_SOMENTE_PLANO=TRUE Rscript fontes/inep/01_extracao_inep.R

# teste rápido: duas UFs e anos recentes
PAINEL_UFS="MG,ES" PAINEL_ANO_INICIAL=2022 Rscript fontes/inep/02_tratamento_inep.R
```

O script 01 valida cada ZIP (assinatura, membros esperados e colunas obrigatórias no cabeçalho) e só termina com erro se algum arquivo falhar; o 02 processa apenas os fluxos com ZIPs presentes e avisa sobre os ausentes.

## Observações metodológicas

- **Mudanças de layout tratadas**
  - Censo Escolar: 2007–2024 vêm em um único CSV escola-nível (`microdados_ed_basica_<ano>.csv`, latin1, `;`); 2025 mudou para `Tabela_Escola/Tabela_Matricula/Tabela_Docente_<ano>_V2.csv`, cruzadas por `CO_ENTIDADE` (exige uma linha por escola em cada tabela).
  - Taxas de rendimento: planilhas `.xls` (2007–2011) e `.xlsx` (2012+). Dois layouts de cabeçalho: nomes de campo (`CO_MUNICIPIO`, `NO_CATEGORIA`/`NO_DEPENDENCIA`, `1_CAT_FUN`…) ou rótulos descritivos em várias linhas com células mescladas ("Código do Município", "Localização", "Rede", "Total Reprovação no Ens. Fundamental"…). As colunas são identificadas **pelo nome completo do total da etapa, nunca por posição** (em 2011 o total aparece no início de cada bloco). Planilhas com uma aba por região são empilhadas. Valores em pontos percentuais; se uma edição vier em fração (0–1), a escala é corrigida.
  - Ideb: só a edição mais recente com as três etapas municipais é usada (traz toda a série). Indicador = rede **pública** (estadual + municipal), como divulgado pelo Inep; não há média entre etapas.
  - Enem: até 2023 `MICRODADOS_ENEM_<ano>.csv`; de 2024 em diante `RESULTADOS_<ano>.csv` (notas) + `PARTICIPANTES_<ano>.csv` (escola), cruzados por `NU_INSCRICAO` quando o município da escola não está nos resultados. As médias usam o **município da escola** (`CO_MUNICIPIO_ESC`, informado só para concluintes do ensino médio), logo cobrem os concluintes daquele ano, não todos os inscritos do município.
  - Censo Superior: aliases anuais de colunas (`CO_MUNICIPIO_IES`/`CO_MUNICIPIO`, `QT_MAT`/`QT_MATRICULA_CURSO`…, `QT_DOC_EXE`/`QT_DOCENTE_EXE` em 2009). Os pacotes de 2009–2024 não trazem tabela individual de docentes; usa-se o total por IES do cadastro. Matrículas EaD ou cursos sem município informado são descartados quando o cadastro de cursos tem coluna de município (município do curso prevalece sobre a sede).
- **Docentes (`num_professores`)**: `QT_DOC_BAS` é o total de docentes por escola sem somar etapas; a soma municipal ainda pode contar a mesma pessoa em mais de uma escola. Anos sem `QT_DOC_BAS` ficam `NA` (não há fallback por soma de etapas).
- **Rede pública × total**: taxas de rendimento e Censo Escolar são totais do município (todas as redes); Ideb é rede pública; Enem inclui escolas públicas e privadas; Censo Superior inclui IES públicas e privadas.
- Faltantes ficam `NA`; zeros só quando a fonte os informa. Códigos fora do dicionário oficial do IBGE (5.570 municípios) são descartados com aviso.
