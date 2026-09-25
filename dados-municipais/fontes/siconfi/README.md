# STN/SICONFI – Finanças municipais: DCA e RREO (`siconfi`)

## Fonte

- **Órgão:** Secretaria do Tesouro Nacional (STN) – Sistema de Informações Contábeis e Fiscais do Setor Público Brasileiro (SICONFI).
- **Conjuntos:** Declaração de Contas Anuais (DCA) – anexos I-C (receitas orçamentárias), I-D (despesas por natureza) e I-E (despesas por função); Relatório Resumido da Execução Orçamentária (RREO) – Anexo 06 (resultados primário e nominal).
- **Página:** https://siconfi.tesouro.gov.br/
- **Documentação da API:** https://apidatalake.tesouro.gov.br/docs/siconfi/
- **Acesso:** API pública, sem chave, limitada a ~1 requisição por segundo.

## Endpoints

| Uso | URL |
|---|---|
| Cadastro de entes (5.598 entes; `esfera = "M"` são os 5.570 municípios) | `https://apidatalake.tesouro.gov.br/ords/siconfi/tt/entes` |
| DCA de um ente-exercício (todos os anexos em uma resposta) | `https://apidatalake.tesouro.gov.br/ords/siconfi/tt/dca?an_exercicio=<ano>&id_ente=<cod_ibge>` |
| RREO Anexo 06, encerramento do exercício | `https://apidatalake.tesouro.gov.br/ords/siconfi/tt/rreo?an_exercicio=<ano>&nr_periodo=6&co_tipo_demonstrativo=RREO&no_anexo=RREO-Anexo%2006&co_esfera=M&id_ente=<cod_ibge>` |

A API só aceita consultas **ente a ente** (`id_ente` obrigatório) e responde com o envelope `items/hasMore/limit/offset/count`; o script percorre as páginas até `hasMore = false`. Cada item traz `exercicio, instituicao, cod_ibge, uf, anexo, rotulo, coluna, cod_conta, conta, valor` (o RREO acrescenta `demonstrativo, periodo, periodicidade`).

Para o RREO, `co_tipo_demonstrativo` é obrigatório na prática (sem ele a resposta vem vazia). O script tenta, em ordem: `RREO` (6º bimestre), `RREO Simplificado` (6º bimestre, municípios com menos de 50 mil habitantes) e `RREO Simplificado` com `nr_periodo=2` (publicação semestral, LRF art. 63; aceito só quando `periodicidade` começa com "S"). A modalidade que deu certo para um ente é tentada primeiro nos exercícios seguintes, o que reduz o número de requisições.

## Indicadores (`siconfi_municipal.csv`)

Uma linha por município-ano. Chaves: `codigo_municipio` (7 dígitos), `nome_municipio`, `uf`, `ano`. Todos os valores em **R$ correntes (nominais)**.

| variável | descrição | unidade | conta / anexo de origem |
|---|---|---|---|
| `receita_total` | Total das receitas orçamentárias realizadas, líquidas de deduções | R$ correntes | DCA I-C, linha `TotalReceitas` |
| `receita_corrente` | Receitas correntes, líquidas de deduções | R$ correntes | DCA I-C, natureza 1.0.0.0 |
| `receita_tributaria` | Impostos, taxas e contribuições de melhoria ("Receita Tributária" até 2017), líquidos de deduções | R$ correntes | DCA I-C, natureza 1.1.0.0 |
| `transferencias_correntes` | Transferências correntes recebidas, líquidas de deduções | R$ correntes | DCA I-C, natureza 1.7.0.0 |
| `transferencias_federais` | Transferências correntes da União | R$ correntes | DCA I-C, 1.7.2.1 (até 2017) / 1.7.1.0 (2018+) |
| `transferencias_estaduais` | Transferências correntes dos Estados | R$ correntes | DCA I-C, 1.7.2.2 (até 2017) / 1.7.2.0 (2018+) |
| `fpm` | Cota-parte do Fundo de Participação dos Municípios | R$ correntes | DCA I-C, 1.7.2.1.01.02 (até 2017); 1.7.1.8.01.2 + 1.7.1.8.01.3 + 1.7.1.8.01.4 (2018–2021); 1.7.1.1.51 (2022+) |
| `icms_cota_parte` | Cota-parte do ICMS | R$ correntes | DCA I-C, 1.7.2.2.01.01 (até 2017); 1.7.2.8.01.1 (2018–2021); 1.7.2.1.50 (2022+) |
| `receita_capital` | Receitas de capital, líquidas de deduções | R$ correntes | DCA I-C, natureza 2.0.0.0 |
| `despesa_total` | Total geral da despesa paga | R$ correntes | DCA I-D, linha `TotalDespesas`, coluna "Despesas Pagas" |
| `despesa_pessoal` | Despesas pagas com pessoal e encargos sociais | R$ correntes | DCA I-D, natureza 3.1, coluna "Despesas Pagas" |
| `despesa_saude` | Despesas pagas na função 10 – Saúde | R$ correntes | DCA I-E, linha "10 - Saúde", coluna "Despesas Pagas" |
| `despesa_educacao` | Despesas pagas na função 12 – Educação | R$ correntes | DCA I-E, "12 - Educação" |
| `despesa_cultura` | Despesas pagas na função 13 – Cultura | R$ correntes | DCA I-E, "13 - Cultura" |
| `despesa_urbanismo` | Despesas pagas na função 15 – Urbanismo | R$ correntes | DCA I-E, "15 - Urbanismo" |
| `despesa_habitacao` | Despesas pagas na função 16 – Habitação | R$ correntes | DCA I-E, "16 - Habitação" |
| `despesa_saneamento` | Despesas pagas na função 17 – Saneamento | R$ correntes | DCA I-E, "17 - Saneamento" |
| `despesa_infraestrutura` | `despesa_urbanismo + despesa_habitacao + despesa_saneamento` | R$ correntes | derivada |
| `resultado_nominal` | Resultado nominal "acima da linha", sem RPPS quando discriminado; pode ser negativo | R$ correntes | RREO Anexo 06, `ResultadoNominalAcimaDaLinhaSemRPPS` (ou `ResultadoNominalAcimaDaLinha` em 2018–2019), coluna VALOR / VALOR INCORRIDO |
| `resultado_primario` | Resultado primário "acima da linha", sem RPPS quando discriminado; pode ser negativo | R$ correntes | RREO Anexo 06, `ResultadoPrimarioSemRPPSAcimaDaLinha` (ou `RREO6ResultadoPrimarioEstadosMunicipios` na versão única, 2018–2019) |

Regras de cálculo (herdadas da rotina original e verificadas na API):

- **Receitas líquidas:** para cada natureza somam-se as colunas `Receitas Brutas Realizadas` (em 2013, `Receitas Realizadas`) e subtraem-se todas as colunas `Deduções ...` (FUNDEB e outras).
- **Despesas:** sempre a coluna **Despesas Pagas** (não empenhadas nem liquidadas). No I-E entram apenas as linhas de função de primeiro nível (`"10 - Saúde"`); somar subfunções (`"10.301 - ..."`) duplicaria os valores. Linhas intraorçamentárias (`DI...`) do I-D ficam fora.
- **Zero estrutural:** se o ente entregou o anexo mas a conta não aparece, o indicador é **0** (a conta não teve movimento). Se o anexo não foi entregue (não declarante), o indicador fica **NA**. No RREO, linha ausente fica **NA**. Nunca se imputa nem se preenche com zero o que a fonte não informa.
- **Resultados:** uma única linha por indicador; quando existem as versões "com RPPS" e "sem RPPS", usa-se a "sem RPPS"; nos exercícios em que a API só traz a versão única (2018–2019), usa-se essa.

## Cobertura temporal e periodicidade

- **DCA:** 2013 até o último exercício encerrado (`ano corrente − 1`). Quebras de plano de contas: códigos de receita com 12 dígitos até 2017 (`1.7.2.1.00.00.00`) e com 10 dígitos a partir de 2018 (`1.7.1.0.00.0.0`); em 2013 os anexos vêm sem o prefixo "DCA-" e as colunas se chamam `Receitas Realizadas`/`Deduções da Receita`. O script trata os três formatos. Atenção: a natureza `1.7.2.1` significa "Transferências da União" até 2017 e "Participação na Receita dos Estados" a partir de 2022 – a chave de seleção inclui o formato do código para não misturar.
- **RREO Anexo 06:** por padrão de **2018** em diante (`SICONFI_ANO_INICIAL_RREO`). Entre 2015 e 2017 o Anexo 06 tinha o leiaute antigo (resultado primário por despesas empenhadas/liquidadas, sem "acima da linha"; o resultado nominal ficava no Anexo 05) e a API não traz RREO anterior a 2015; esses anos não são coletados por padrão. Em 2018 os códigos ainda não distinguem "com/sem RPPS" (série com quebra metodológica leve entre 2018–2019 e 2020+).
- **Periodicidade:** anual. A DCA do exercício X é entregue até 30 de abril de X+1 (com retificações ao longo do ano); o RREO do 6º bimestre sai até 30 de janeiro de X+1.
- **Municípios:** todos os 5.570 (entes com `esfera = "M"`); municípios que não entregaram a declaração simplesmente não têm linha para aquele ano-anexo.

## Tempo estimado de coleta

A API limita a ~1 requisição/segundo (o script pausa no mínimo 1,05 s entre requisições e aplica backoff exponencial em falhas). Latência observada: DCA 2–8 s por ente (respostas de 250–450 KB), RREO 1–5 s.

| etapa | requisições por exercício | tempo por exercício |
|---|---|---|
| DCA (1 requisição por ente) | ~5.570 | ~3 a 5 h |
| RREO Anexo 06 (1 a 3 requisições por ente; ~1 após aprender a modalidade) | ~6.000 a 11.000 | ~2 a 4 h |
| Série completa 2013–2025 (DCA) + 2018–2025 (RREO) | ~120 mil | **~60 a 90 h** (2,5 a 4 dias) |

Por isso a extração é **retomável**: cada ente-exercício-endpoint vira um arquivo `dados/brutos/siconfi/<endpoint>/<ano>/<cod_ibge>.json.gz` (gzip; ~20–40 KB para a DCA, ~5 KB para o RREO; série completa ≈ 2 GB) e os já existentes são pulados. Os exercícios mais recentes são coletados primeiro. Entes sem dados geram arquivo com `items: []` (< 400 bytes), que também é pulado; para reconsultá-los (declarações atrasadas do último exercício) use `SICONFI_RECONSULTAR_VAZIOS=TRUE`.

**Caminho rápido para a carga inicial – FINBRA.** A STN publica os mesmos dados consolidados por anexo e exercício, para todos os entes de uma vez, na consulta FINBRA: https://siconfi.tesouro.gov.br/siconfi/pages/public/consulta_finbra/finbra_list.jsf ("Dados Contábeis" → escolher exercício, esfera Municípios e anexo I-C, I-D ou I-E → CSV). O download é manual (página JSF, sem URL direta). Coloque os CSVs em `dados/brutos/siconfi/finbra/` (um arquivo por exercício-anexo) e o script 02 os lê para os ente-exercícios que ainda não têm arquivo da API. O leitor espera o leiaute padrão do FINBRA (linhas de metadados com `Ano:` e `Anexo`, cabeçalho `Instituição;Cod.IBGE;UF;População;Coluna;Conta;Valor`, separador `;`, decimal `,`, Latin-1) e **não foi testado com um arquivo real** – confira a primeira carga (o script aborta com mensagem clara se o cabeçalho não for reconhecido).

## Dependências

R base + `jsonlite` + `curl` (biblioteca comum). O tratamento é escrito em R base (não exige `data.table`; se instalado, apenas acelera a leitura/gravação de CSV). Nenhum pacote é instalado pelos scripts.

## Como rodar

```bash
Rscript fontes/siconfi/01_extracao_siconfi.R      # retomável; pode ser interrompido e reexecutado
Rscript fontes/siconfi/02_tratamento_siconfi.R
```

Recortes para testes ou cargas parciais (variáveis de ambiente):

```bash
PAINEL_UFS="AC,RR" PAINEL_ANO_INICIAL=2023 Rscript fontes/siconfi/01_extracao_siconfi.R   # 37 municípios, 2023-2025
SICONFI_ANO_FINAL=2024 Rscript fontes/siconfi/01_extracao_siconfi.R                         # trava o último exercício
SICONFI_ANO_INICIAL_RREO=2015 Rscript fontes/siconfi/01_extracao_siconfi.R                  # baixa também o RREO antigo (não tratado)
SICONFI_RECONSULTAR_VAZIOS=TRUE Rscript fontes/siconfi/01_extracao_siconfi.R                # reconsulta entes sem dados
SICONFI_PAUSA_SEGUNDOS=1.5 Rscript fontes/siconfi/01_extracao_siconfi.R                     # pausa maior (mínimo 1,05 s)
```

O script 02 usa um cache por endpoint-exercício em `dados/tratados/siconfi/intermediario/` (linhas já selecionadas), invalidado automaticamente quando surgem arquivos novos na pasta do exercício. Se as regras de seleção mudarem, apague essa pasta.

## Observações metodológicas

- **Entes sem declaração:** a API devolve `items: []`. A base tratada não tem linha para o município-ano-anexo correspondente (NA nos indicadores daquele anexo); a ausência nunca é convertida em zero. A cobertura costuma ficar em 90–97% dos municípios para a DCA e menor para o Anexo 06 do RREO.
- **DCA retificada:** a API entrega sempre a versão vigente (a mais recente homologada). Como os arquivos gravados são reutilizados, uma retificação só entra ao apagar o arquivo do ente-exercício (ou a pasta do exercício) e rodar de novo o 01. Sugestão: reprocessar o último exercício alguns meses após o prazo de entrega.
- **Quebras de plano de contas:** (i) 2018 – novo ementário da receita (10 dígitos), com reclassificação de transferências (convênios e outras transferências da União passam a compor `1.7.1`, o que altera levemente `transferencias_federais/estaduais` em relação a `1.7.2.1/1.7.2.2` do plano antigo); (ii) 2022 – reclassificação das transferências constitucionais (FPM em `1.7.1.1.51`, ICMS em `1.7.2.1.50`); (iii) 2013 – primeiro exercício no SICONFI, com anexos e colunas nomeados de forma diferente. Os mapeamentos por plano foram verificados na API para um ente em 2013, 2014, 2017, 2018, 2020, 2022 e 2023.
- **RREO Anexo 06:** valores do 6º bimestre (acumulado do exercício) na coluna VALOR; em 2018 a coluna se chama VALOR INCORRIDO. Municípios com publicação semestral simplificada são buscados no 2º semestre. Municípios que não publicam o Anexo 06 no SICONFI ficam NA.
- **Receitas intraorçamentárias:** `receita_total` e `despesa_total` são os totais gerais das declarações (incluem as operações intraorçamentárias); os demais agregados (`receita_corrente`, `despesa_pessoal` etc.) referem-se às contas "exceto intraorçamentárias".
- **Valores nominais:** nenhum deflacionamento é aplicado; a aplicação deflaciona quando necessário (a biblioteca comum oferece `deflator_ipca_anual`).
- **Consistência:** `receita_total ≈ receita_corrente + receita_capital + receitas intraorçamentárias`; `despesa_infraestrutura` é uma soma de funções e não um conceito da STN.
