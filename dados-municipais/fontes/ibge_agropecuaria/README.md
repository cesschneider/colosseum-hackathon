# IBGE – Produção agropecuária municipal (PAM e PPM/aquicultura)

Valor da produção e área colhida das lavouras temporárias e permanentes (Produção Agrícola Municipal – PAM) e valor e produção em quilogramas da aquicultura (Pesquisa da Pecuária Municipal – PPM), para **todos os municípios do Brasil**, uma linha por município-ano.

## Fonte e endpoints

| Item | Detalhe |
|---|---|
| Órgão | IBGE – SIDRA |
| Tabelas | 1612 (lavouras temporárias), 1613 (lavouras permanentes), 3940 (aquicultura, por tipo de produto) |
| Variáveis SIDRA | 215 = Valor da produção; 216 = Área colhida; 4146 = Produção da aquicultura |
| Categorias | 1612: `c81/0` (total dos produtos); 1613: `c82/0` (total); 3940: `c654/0` (total, para o valor) e 21 produtos da `c654` medidos em kg (para a produção) |
| API de valores | `https://apisidra.ibge.gov.br/values/t/<tabela>/n6/in n3 <UF>/v/<variáveis>/p/<início>-<fim>/c…` (uma UF por vez, via `sidra_consultar`) |
| API de períodos | `https://servicodados.ibge.gov.br/api/v3/agregados/<tabela>/periodos` (descobre o último ano publicado) |
| Deflator | IPCA mensal, SGS/BCB série 433 (`https://api.bcb.gov.br/dados/serie/bcdata.sgs.433/dados`), via `deflator_ipca_anual()` |
| Páginas | https://sidra.ibge.gov.br/tabela/1612 · https://sidra.ibge.gov.br/tabela/1613 · https://sidra.ibge.gov.br/tabela/3940 |

## Arquivos

Brutos (`dados/brutos/ibge_agropecuaria/`), retorno da API preservado como veio (todas as colunas do SIDRA, valores em texto):

| Arquivo | Conteúdo |
|---|---|
| `sidra_1612_lavouras_temporarias.rds` | tabela 1612, variáveis 215 e 216, total dos produtos, 1974 em diante |
| `sidra_1613_lavouras_permanentes.rds` | tabela 1613, variáveis 215 e 216, total dos produtos, 1974 em diante |
| `sidra_3940_aquicultura_valor.rds` | tabela 3940, variável 215, total dos produtos, 2013 em diante |
| `sidra_3940_aquicultura_producao_kg.rds` | tabela 3940, variável 4146, 21 produtos em kg, 2013 em diante |
| `deflator_ipca_anual.csv` | fator IPCA por ano (média anual do índice), base 2024 |

Tratados (`dados/tratados/ibge_agropecuaria/`): `ibge_agropecuaria_municipal.csv` (chaves `codigo_municipio`, `nome_municipio`, `uf`, `ano`) e `ibge_agropecuaria_dicionario_variaveis.csv`.

## Indicadores

| Variável | Descrição | Unidade |
|---|---|---|
| `valor_producao_lavouras_temporarias` | Valor da produção das lavouras temporárias (total dos produtos, tabela 1612) | mil R$ correntes |
| `valor_producao_lavouras_permanentes` | Valor da produção das lavouras permanentes (total dos produtos, tabela 1613) | mil R$ correntes |
| `valor_producao_agricola_total` | Temporárias + permanentes; NA se qualquer componente faltar | mil R$ correntes |
| `area_colhida_temporarias` | Área colhida das lavouras temporárias (tabela 1612) | hectares |
| `area_colhida_permanentes` | Área colhida das lavouras permanentes (tabela 1613) | hectares |
| `area_colhida_total` | Temporárias + permanentes; NA se qualquer componente faltar | hectares |
| `valor_producao_aquicultura` | Valor da produção da aquicultura (total dos produtos, tabela 3940) | mil R$ correntes |
| `producao_aquicultura_kg` | Soma de 21 produtos da aquicultura medidos em quilogramas (peixes, camarão, ostras/vieiras/mexilhões e outros produtos); exclui alevinos, larvas/pós-larvas de camarão e sementes de moluscos, medidos em milheiros | kg |
| `valor_producao_lavouras_temporarias_reais_2024` | Idem, a preços de 2024 (IPCA) | mil R$ de 2024 |
| `valor_producao_lavouras_permanentes_reais_2024` | Idem, a preços de 2024 (IPCA) | mil R$ de 2024 |
| `valor_producao_agricola_total_reais_2024` | Idem, a preços de 2024 (IPCA) | mil R$ de 2024 |
| `valor_producao_aquicultura_reais_2024` | Idem, a preços de 2024 (IPCA) | mil R$ de 2024 |

As colunas nominais são sempre gravadas; as `_reais_2024` são um complemento (disponíveis de 1995 em diante).

## Cobertura temporal e periodicidade

- Periodicidade anual; ano de referência = ano-safra/ano civil da pesquisa.
- PAM (tabelas 1612 e 1613): 1974 até o último ano publicado (2025 na data desta versão). Área colhida vale para toda a série; valor da produção apenas de 1994 em diante (ver observações).
- PPM/aquicultura (tabela 3940): 2013 até o último ano publicado (2024 na data desta versão).
- A base tratada tem uma linha por município-ano com ao menos um indicador informado; anos anteriores à instalação de um município (SIDRA devolve `...`) não geram linha.
- A API de agregados informa os períodos publicados, então uma nova divulgação anual é detectada automaticamente no script 01 – desde que os brutos sejam rebaixados (ver "Como rodar").

## Tamanho e tempo estimados (Brasil inteiro)

- A API limita cada requisição a 50.000 valores (municípios × variáveis × períodos × categorias). O script 01 fatia os períodos em blocos dimensionados pela maior UF ativa (MG, 853 municípios): PAM em 2 blocos por tabela, aquicultura em kg em blocos de 2 anos. Resultado: cerca de 300 requisições (27 UFs × 11 blocos).
- Volume aproximado: 2,6 milhões de linhas (1612 ≈ 580 mil; 1613 ≈ 580 mil; 3940 valor ≈ 67 mil; 3940 kg ≈ 1,4 milhão), algo como 0,5 GB de JSON transferido (≈ 200 bytes por valor); em RDS comprimido os brutos ocupam dezenas de MB.
- Tempo: tipicamente 30 a 60 minutos para a extração completa, dependendo da resposta do SIDRA; o tratamento leva poucos minutos. Com `PAINEL_UFS=AC` a extração leva menos de 30 segundos.

## Dependências

R base + `jsonlite` + `curl` (as mesmas da biblioteca comum). `data.table` é opcional (acelera leitura/gravação de CSV quando presente). Nenhum download manual, nenhum 7-Zip.

## Como rodar

```bash
Rscript fontes/ibge_agropecuaria/01_extracao_ibge_agropecuaria.R
Rscript fontes/ibge_agropecuaria/02_tratamento_ibge_agropecuaria.R
```

- Teste rápido: `PAINEL_UFS=AC PAINEL_DADOS=/tmp/dados_teste Rscript …` (use `PAINEL_DADOS` para não misturar brutos parciais de teste com a pasta de dados real; o script 02 recusa brutos que não cubram todas as UFs ativas).
- Os brutos do SIDRA cobrem a série inteira, por isso são reutilizados quando já existem. Para incorporar uma nova divulgação da PAM/PPM, rode o 01 com `PAINEL_REBAIXAR=TRUE`. O deflator é sempre rebaixado (série pequena; se o BCB estiver fora do ar, o arquivo anterior é reaproveitado).
- `PAINEL_ANO_INICIAL=2020` limita os períodos pedidos à API (intervalo `2020-<ano atual>`).
- O ano-base das colunas deflacionadas é a constante `ANO_BASE_PRECOS` no script 01 (2024); o script 02 lê o ano-base do próprio arquivo do deflator e nomeia as colunas de acordo.

## Observações metodológicas

1. **Símbolos do SIDRA.** `-` significa zero absoluto (não resultante de arredondamento) e é convertido em 0; `...` (não se aplica, p. ex. município ainda não instalado), `..` (não disponível) e `X` (omitido por sigilo) viram NA. Na aquicultura por produto o `-` é frequente (município sem aquele produto), por isso a soma em kg resulta em 0 quando o município informa zero em todos os produtos e em NA somente quando nenhum produto tem valor.
2. **Moeda.** No SIDRA a variável 215 muda de unidade ao longo da série: Mil Cruzeiros (1974–1985, 1990–1992), Mil Cruzados (1986–1988), Mil Cruzados Novos (1989), Mil Cruzeiros Reais (1993) e Mil Reais (1994 em diante). Só os anos em Mil Reais são mantidos; os demais ficam NA na coluna de valor (a área colhida, em hectares, é mantida desde 1974). A conversão se baseia na coluna "Unidade de Medida" devolvida linha a linha pela API.
3. **Totais agrícolas.** `valor_producao_agricola_total` e `area_colhida_total` são calculados apenas quando os dois componentes (temporárias e permanentes) existem; caso contrário ficam NA. Nada é preenchido com zero além do que a fonte declara como zero.
4. **Aquicultura em kg.** Soma dos códigos 32861, 32865–32881, 32887, 32889 e 32891 da classificação 654 (peixes por espécie, "outros peixes", camarão, ostras/vieiras/mexilhões e "outros produtos"). Ficam de fora alevinos (32886), larvas e pós-larvas de camarão (32888) e sementes de moluscos (32890), medidos em milheiros. O produto 32891 ("Outros produtos: rã, jacaré, siri, caranguejo, lagosta etc.") vem sem unidade declarada nos metadados da API ("Nenhuma"); a PPM o publica em quilogramas e ele é somado como tal. Não há colunas por produto.
5. **Aquicultura – valor.** Mantido em mil R$ correntes, como a fonte (sem conversão para R$).
6. **Deflator.** Fator = média anual do índice IPCA (SGS 433) do ano-base dividida pela média anual do índice de cada ano, calculado por `deflator_ipca_anual()`; adequado a fluxos anuais como o valor da produção. O ano de 1994 é descartado porque a série da biblioteca começa em dezembro/1994 (a média anual não seria representativa); as colunas `_reais_2024` existem de 1995 em diante. Valores nominais são sempre preservados.
7. **Malha municipal.** A API responde com a malha municipal vigente para todos os anos; municípios instalados depois de 1974 aparecem com `...` nos anos anteriores à instalação e, por isso, só entram na base a partir do primeiro ano com dado. Códigos fora do dicionário oficial de municípios são descartados (com aviso no log).
8. **Revisões.** O IBGE revisa o último ano da PAM na divulgação seguinte; ao rebaixar os brutos, os valores do ano anterior podem mudar.
