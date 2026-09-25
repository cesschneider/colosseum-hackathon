# bcb_estban — ESTBAN: Estatística Bancária Mensal por Município (BCB)

## Fonte

- **Órgão**: Banco Central do Brasil (BCB).
- **Conjunto**: ESTBAN — Estatística Bancária Mensal por Município (documento 4500). Saldos mensais dos principais verbetes do balancete das agências bancárias, publicados por instituição × município; a rotina soma as agências de cada município.
- **Página**: <https://www.bcb.gov.br/estatisticas/estatisticabancariamunicipios>
- **Catálogo (JSON, descoberta dinâmica dos arquivos)**:
  `https://www.bcb.gov.br/api/servico/sitebcb/Documentos/byListGuid?tronco=estatisticas&guidLista=f6391806-fd85-43af-acf1-c86d5b8dd6df&ordem=DataDocumento%20desc&pasta=municipio`
- **Arquivos mensais**: `https://www.bcb.gov.br/content/estatisticas/estatistica_bancaria_estban/municipio/AAAAMM_ESTBAN.ZIP` (histórico), `AAAAMM_ESTBAN.csv` (2023-01) e `AAAAMM_ESTBAN.csv.zip` (2023-02 em diante). O catálogo registra o nome correto de cada mês, por isso ele é a fonte da lista de downloads.

## Indicadores (`bcb_estban_municipal.csv`, uma linha por município-mês)

| variável | descrição | unidade |
|---|---|---|
| `numero_agencias` | Agências bancárias com balancete processado no mês (soma de `AGEN_PROCESSADAS`) | agências |
| `operacoes_credito` | Saldo de operações de crédito (verbete 160) | R$ correntes |
| `emprestimos_titulos_descontados` | Saldo de empréstimos e títulos descontados (verbete 161) | R$ correntes |
| `credito_rural` | Financiamentos rurais e agroindustriais: soma dos verbetes 163 a 167 publicados no mês (163 e 167 sempre presentes) | R$ correntes |
| `credito_imobiliario` | Financiamentos imobiliários (verbete 169) | R$ correntes |
| `depositos_vista` | Depósitos à vista (coluna agregada dos verbetes 401 a 419) | R$ correntes |
| `depositos_poupanca` | Depósitos de poupança (verbete 420) | R$ correntes |
| `depositos_prazo` | Depósitos a prazo (verbete 432) | R$ correntes |
| `depositos_total` | À vista + poupança + interfinanceiros (430 e 431) + a prazo | R$ correntes |
| `variacao_depositos_vista` | Variação do saldo à vista em relação ao mês anterior (só quando o mês anterior existe para o município) | R$ correntes |
| `variacao_depositos_poupanca` | Idem, poupança | R$ correntes |
| `variacao_depositos_prazo` | Idem, a prazo | R$ correntes |

Colunas de chave: `codigo_municipio` (7 dígitos), `nome_municipio`, `uf`, `ano`, `mes`.

## Cobertura e periodicidade

- **Territorial**: todos os municípios do Brasil que possuem agência bancária no mês (cerca de 3.000 a 3.500 dos 5.570; municípios sem agência simplesmente não aparecem — a base não é balanceada artificialmente).
- **Temporal**: 2000-01 até o mês mais recente publicado (o catálogo remonta a 1988-07; o início em 2000 é o padrão do projeto e pode ser alterado em `ANO_INICIAL`). Defasagem de publicação de aproximadamente 2 a 3 meses.
- **Periodicidade**: mensal (`mensal = TRUE`). Os valores são saldos (estoques) no último dia do mês.

## Tamanho e tempo

- Download: ~320 arquivos de 0,9 a 1,3 MB (≈ 350 MB no total desde 2000). Primeira execução: 5 a 15 minutos, conforme a conexão; execuções seguintes reutilizam os arquivos cujo tamanho confere com o catálogo (meses republicados pelo BCB são rebaixados automaticamente).
- Tratamento: cada arquivo tem ~8 a 11 mil linhas (instituição × município); os zips são descompactados em pasta temporária e descartados. Alguns minutos no total; a base final tem ~1,1 milhão de linhas (≈ 130 MB em CSV).

## Dependências

- R ≥ 4.1 com `jsonlite`, `curl` (script 01) e `data.table` (script 02). Não exige 7-Zip nem ferramentas externas.
- Dicionário oficial de municípios (`dados/auxiliares/dicionario_municipios.csv`), criado automaticamente pela biblioteca comum se não existir.

## Como rodar

```bash
Rscript fontes/bcb_estban/01_extracao_bcb_estban.R    # baixa/reutiliza os arquivos mensais
Rscript fontes/bcb_estban/02_tratamento_bcb_estban.R  # gera dados/tratados/bcb_estban/
```

Para um teste rápido, restrinja o período: `PAINEL_ANO_INICIAL=2024` (vale para os dois scripts). `PAINEL_REBAIXAR=TRUE` força novo download de tudo.

## Observações metodológicas

- **Layout dos CSVs**: duas linhas de título, cabeçalho na terceira linha, separador `;`, codificação Latin-1, valores inteiros em R$ correntes (sem separador decimal). O layout tinha 66 colunas até 2022 e passou a 54 colunas; os verbetes rurais 164, 165 e 166 deixaram de ser publicados separadamente (por isso `credito_rural` soma os verbetes 163 a 167 que existirem no mês, exigindo 163 e 167). Os nomes das colunas mudam ao longo do tempo (ex.: `VERBETE_167_...+VERBETE_168_...`), e a rotina localiza cada verbete pelo prefixo `VERBETE_<código>`.
- **Agregação**: soma dos saldos de todas as instituições/agências de cada município no mês. Linhas sem `CODMUN_IBGE` (registros técnicos com 0 agências) são descartadas. Os códigos vêm com 7 dígitos; um eventual código de 6 dígitos é convertido pelo dicionário oficial.
- **Valores nominais**: a base mantém R$ correntes, conforme a convenção do painel. Para comparar ao longo do tempo, deflacione na aplicação (ex.: `deflator_ipca_anual(ano_base)` da biblioteca comum, ou o índice mensal do IPCA via `bcb_sgs(433)`).
- **Variações mensais**: primeira diferença dos saldos de depósitos; podem ser negativas (saques líquidos) e ficam `NA` no primeiro mês de cada município ou quando há lacuna no mês anterior.
- **Faltantes**: quando todas as agências de um município têm o verbete vazio, o indicador fica `NA` (não é convertido em zero).
