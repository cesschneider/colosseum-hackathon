# datasus_populacao — Estimativas populacionais por município e faixa etária (DataSUS/TabNet)

## Fonte

Ministério da Saúde / DataSUS — TabNet, "População Residente — Estudo de Estimativas Populacionais por Município, Idade e Sexo 2000-2025 — Brasil" (estudo MS/SVSA em parceria com a RIPSA, base para os indicadores de saúde). É a mesma população que o Ministério da Saúde usa como denominador das taxas do SIM/SINASC, publicada para **todos os anos** a partir de 2000 (inclusive anos de Censo).

- Formulário: `http://tabnet.datasus.gov.br/cgi/deftohtm.exe?ibge/cnv/popsvs2024br.def`
- Consulta: `POST http://tabnet.datasus.gov.br/cgi/tabcgi.exe?ibge/cnv/popsvs2024br.def` com corpo `application/x-www-form-urlencoded` (`Linha=Município`, `Coluna=Faixa_Etária_1`, `Incremento=População_residente`, `Arquivos=popAA.dbf`, todas as categorias de região/UF/município/sexo/faixa, `formato=prn`).
- O nome do `.def` identifica a **edição** do estudo (a edição 2024 cobre 2000–2025). O script 01 tenta as edições mais novas primeiro (`popsvs<ano+1>br.def` até `popsvs2024br.def`) e usa a primeira que devolve o formulário; os anos são descobertos nas opções `<OPTION VALUE="popAA.dbf">AAAA` do campo `Arquivos`.

## Saídas

- `dados/brutos/datasus_populacao/datasus_populacao_faixa_etaria_<ano>.html` — resposta bruta do TabNet (HTML latin1 com a tabela `.prn` dentro de `<PRE>`), um arquivo por ano (~430 KB cada).
- `dados/tratados/datasus_populacao/datasus_populacao_municipal.csv` — uma linha por município-ano.
- `dados/tratados/datasus_populacao/datasus_populacao_dicionario_variaveis.csv`.

## Indicadores

| variável | descrição | unidade | regra |
|---|---|---|---|
| `populacao_total` | população residente estimada | habitantes | coluna "Total" do TabNet; validada contra a soma das faixas |
| `populacao_0_14` | população de 0 a 14 anos | habitantes | faixas 0-4 + 5-9 + 10-14 |
| `populacao_15_59` | população de 15 a 59 anos | habitantes | faixas 15-19 + 20-29 + 30-39 + 40-49 + 50-59 |
| `populacao_60_mais` | população de 60 anos ou mais | habitantes | faixas 60-69 + 70-79 + 80 e mais |
| `razao_dependencia_jovem` | razão de dependência jovem | razão (proporção) | `populacao_0_14 / populacao_15_59` |
| `razao_dependencia_idosa` | razão de dependência idosa | razão (proporção) | `populacao_60_mais / populacao_15_59` |
| `razao_dependencia_total` | razão de dependência total | razão (proporção) | `(populacao_0_14 + populacao_60_mais) / populacao_15_59` |
| `indice_envelhecimento` | índice de envelhecimento | idosos por 100 jovens | `100 * populacao_60_mais / populacao_0_14` |

As razões ficam em proporção (0,20 = 20 dependentes por 100 pessoas de 15-59 anos); o índice de envelhecimento segue a definição RIPSA (60+ por 100 menores de 15). O TabNet publica as faixas 0-4, 5-9, 10-14, 15-19, 20-29, ..., 70-79 e 80+, o que não permite o corte em 65 anos; por isso os grupos são 0-14 / 15-59 / 60+. Denominador zero produz `NA`.

## Cobertura e periodicidade

- Brasil, 5.570 municípios; anos **2000 a 2025** na edição atual (descobertos automaticamente). O ano mais recente é sempre reconsultado, pois pode ser revisado até a edição seguinte.
- Periodicidade anual. Novas edições costumam trazer um ano a mais e podem revisar toda a série (as estimativas são reponderadas pelos Censos).
- Códigos municipais do TabNet têm 6 dígitos (sem dígito verificador): convertidos com `codigo6_para_7()` e o dicionário oficial do IBGE.

## Tamanho e tempo

26 consultas de ~430 KB (≈ 11 MB no total); cada resposta leva de 2 a 10 segundos. Extração completa em poucos minutos. O tratamento é imediato.

## Dependências

R base + `curl` (já exigido pela biblioteca comum). Não usa `data.table`.

## Como rodar

```
Rscript fontes/datasus_populacao/01_extracao_datasus_populacao.R
Rscript fontes/datasus_populacao/02_tratamento_datasus_populacao.R
```

Para testar rápido: `PAINEL_ANO_INICIAL=2023` (só os últimos anos) e/ou `PAINEL_UFS="MG,ES"` (o download é sempre nacional, mas a base tratada fica restrita às UFs ativas). `PAINEL_REBAIXAR=TRUE` refaz todas as consultas.

## Observações metodológicas e armadilhas

- O CGI do TabNet só aceita os nomes dos campos em **latin1**; o corpo do POST usa escapes percentuais deliberados (`Munic%EDpio`, `Faixa_Et%E1ria_1`, ...). Enviar UTF-8 devolve a página "Tabela de conversão não encontrada".
- A resposta é validada antes de substituir o bruto anterior: tamanho mínimo, ausência de página de erro, cabeçalho com "0 a 4 anos" e "80 anos e mais", pelo menos 5.500 linhas municipais e **período igual ao ano pedido** (`Período: AAAA`). Qualquer divergência bloqueia a gravação e o ano é registrado como falha.
- No `.prn`, "-" significa zero e "..." dado indisponível; os números vêm sem separador de milhar.
- O tratamento interrompe se a soma das faixas não reproduzir o total publicado ou se houver código municipal duplicado.
