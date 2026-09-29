# Test Plan — Dados Municipais: E2E Pipeline (R → S3 → API)

**Objetivo:** validar 2 fontes leves do pipeline R do Marcelo, publicando os dados tratados em um bucket S3 da AWS (account eworks-dev, CDK-only) e expondo-os via API de dados que servirá como produto pago (crypto) do hackathon Colosseum.

**Status do plano:** APROVADO PARA EXECUÇÃO (Fase 0 completa)
**Autor:** B.IA
**Data:** 29/09/2026

---

## Contexto técnico verificado

| Item | Estado |
|---|---|
| Pipeline R (22 fontes, ~9.1k linhas) | Branch `feat/dados-municipais` (commit 12c06f4), **merge pendente** |
| Fontes-alvo (leves) | `ibge_pib_municipal` (3–6 min, SIDRA 5938) e `sagicad_bolsa_familia` (~80 MB, mensal) |
| R / Rscript | **NÃO instalado** no host — Fase 0 instala R 4.x + `data.table` |
| AWS | `eworks-dev` (666637312477), hermes-agent user, CDK-only; buckets existentes: `colosseum-poc-benchmark` (benchmark S3 já rodado), `raw-documents-dev` |
| Esquema de saída do pipeline | 1 linha/município-período: `codigo_municipio` (IBGE 7), `nome_municipio`, `uf`, `ano`, `mes` |
| Camada final | `painel_municipal_long.csv` + `catalogo_variaveis.csv` (é o que a aplicação/API consome) |
| PoC Solana | Program `dataset_provenance` (pubkey `6nevE...`) com `store_dataset`/`verify_dataset` — hash on-chain p/ integridade |
| Monetização (PRD) | FR-005: custo USD com preço SOL timestampado; Fase 3 = token-gating/pagamento por acesso |

---

## Fase 0 — Setup (pré-requisitos)

- **0.1** Instalar R 4.x + `Rscript` no host (Ubuntu: `apt install r-base`), verificar versão.
- **0.2** `Rscript dados-municipais/fontes/00_comum/instalar_dependencias.R` — instalar pacotes R (data.table etc.).
- **0.3** Verificar AWS CDK disponível no projeto; bucket destino será criado via CDK (regra CDK-only).
- **0.4** Merge prévio da branch `feat/dados-municipais` no master (ou checkout local da branch) para execução.

## Fase 1 — Extração e tratamento (fonte 1: PIB municipal)

- **1.1** Rodar `01_extracao_ibge_pib_municipal.R` — download SIDRA 5938 + Ipeadata (ESTIMA_PO/POPTOT).
- **1.2** Rodar `02_tratamento_ibge_pib_municipal.R` — gerar `dados/tratados/ibge_pib_municipal/ibge_pib_municipal_municipal.csv`.
- **1.3** Validar: ~200 mil linhas esperadas (5.570 municípios × anos 2002+), cabeçalho conforme contrato (`codigo_municipio`, `nome_municipio`, `uf`, `ano`, indicadores numéricos), sem valores vazios no código IBGE.

## Fase 2 — Extração e tratamento (fonte 2: Bolsa Família)

- **2.1** Rodar `01_extracao_sagicad_bolsa_familia.R` — download MISocial/MDS (~80 MB).
- **2.2** Rodar `02_tratamento_sagicad_bolsa_familia.R` — gerar `sagicad_bolsa_familia_municipal.csv`.
- **2.3** Validar: cobertura mensal (2004-01 → última competência), junção por código IBGE direto (MISocial já traz código), consistência `famílias_beneficiárias ≤ população` (sanity check cruzado com fonte 1).

## Fase 3 — Ingestão S3 (CDK-only)

- **3.1** Criar bucket via CDK no account eworks-dev: `dados-municipais-dev-666637312477-us-east-1` com estrutura `raw/<fonte>/`, `curated/<fonte>/`, `catalog/`.
- **3.2** Upload dos brutos preservados (`dados/brutos/`) → `s3://…/raw/` e tratados (`dados/tratados/`) → `s3://…/curated/`.
- **3.3** Validar: `aws s3 ls` recursivo confere contagem de objetos; ACL privada; SSE-S3; versionamento ON (dados públicos oficiais, reprocessamento auditável).
+ 

## Fase 4 — API de dados (consumo pago)

- **4.1** Definir interface mínima da API: `GET /v1/datasets` (catálogo), `GET /v1/datasets/{fonte}/query` (filtros: municipio, uf, ano) lendo S3 (Athena ou GET direto de CSV). Recomendo **S3 + Athena** para queries por município; GET direto só para catálogo/datasets pequenos.
- **4.2** Proteção: token-gating já previsto no PRD (Fase 3 do produto). API Gateway + Lambda authorizer mapeando token de acesso pago → claims (dataset, período, município permitido). Pagamento em crypto (SOL/USDC) desbloqueia o token.
- **4.3** Infra CDK: API Gateway → Lambda → Athena/S3. Nada manual no console.

## Fase 5 — Integridade + link com PoC Solana (diferencial hackathon)

- **5.1** Para cada dataset curado em S3, calcular SHA-256 do CSV tratado.
- **5.2** Registrar hash on-chain via program `dataset_provenance` (PoC existente, `store_dataset`) — prova de proveniência/integridade do dataset no devnet (assim que faucet destravar).
- **5.3** Validar E2E: `verify_dataset` retorna OK para o CSV no S3; mismatch gera erro esperado.

## Fase 6 — Relatório final

- **6.1** Resultado por fase com evidências (logs, contagens de linhas, `s3 ls`).
- **6.2** Commit + push: plano de teste em `docs/testing/` (repo raiz, fora do epic-1 do PoC Solana), resultados em `docs/research/` + progress.json atualizado.
- **6.3** Entregar: passos concluídos, blockers explícitos, números medidos, caminhos dos artefatos.

---

## Critérios de aceite

1. R instalado e ambas as fontes leves executadas sem erro, com CSVs tratados gerados localmente.
2. Bucket S3 criado via CDK, brutos+tratados versionados, contagem de objetos confere.
3. API de dados retorna dados reais do S3 para os 2 datasets (catálogo + query por município).
4. Hash on-chain registrado no devnet e `verify_dataset` OK (ou bloqueio de faucet explicitado como blocker).
5. Tudo commitado e pushed no repo, com relatório em `docs/research/`.