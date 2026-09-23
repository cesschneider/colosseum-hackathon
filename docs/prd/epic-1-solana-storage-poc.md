# PRD — Epic 1: PoC de Armazenamento de Dados na Rede Solana (com Métricas de Custo & Performance)

**Projeto:** Hackathon Colosseum 2026
**Autor:** @pm (Morgan)
**Data:** 22 Set 2026
**Status:** Draft → (aguardando validação @po)
**Base técnico:** `docs/research/ARMAZENAMENTO-DESCENTRALIZADO-SOLANA.md`, `DECISAO-PLACEMENT-SOLANA-VS-AWS.md`

---

## 1. Visão

Validar, **empiricamente e com números**, quais camadas de armazenamento da rede Solana (e redes descentralizadas adjacentes) são viáveis para o marketplace de dados, medindo **custo real por GB** e **performance** (latência de escrita/leitura, throughput) em cada opção — e comparando contra a baseline AWS já documentada.

**Objetivo do PoC (não é produto):** produzir uma **matriz de benchmark** que responda, com dados medidos e não estimados:
- Quanto custa de verdade armazenar 1 MB / 1 GB / 1 TB em cada camada?
- Qual a latência e o throughput de escrita e leitura?
- Onde Solana ganha e onde perde contra AWS?

---

## 2. Escopo (In / Out)

### IN Scope
- Solana **on-chain (rent)**: escrever dados em contas, medir depósito/custo por byte, reclamar (close) e verificar reembolso.
- Solana **state compression (Merkle/Bubblegum)**: comprimir dados em árvore, medir custo por asset/leaf.
- **Irys**: armazenar snapshot de dataset (permanente e term), medir custo + prova de existência.
- **shdwDrive**: armazenar dados mutáveis, medir custo/ano + latência.
- **AWS baseline**: S3 (Standard, IA, Glacier Deep Archive) para comparação 1:1.
- **Harness de métricas**: coleta unificada de custo (SOL/USDC gasto, USD equivalente) e performance (latência, throughput, tamanho).

### OUT of Scope (Fase 1)
- Token-gating / pagamento por acesso (Fase 3).
- Frontend/dashboard (Fase 2).
- ETL completo dos datasets (já é o Passo 2 do MVP de dados, epics separados).
- Arweave e Filecoin (documentados, mas fora do PoC ativo — foco em Solana + Irys + shdwDrive).

---

## 3. Requisitos Funcionais (FR-*)

### Módulo A — Solana On-Chain (rent)
- **FR-001** — Criar wallet Solana em devnet (e opcional mainnet) com funding.
- **FR-002** — Escrever payload de N bytes em uma conta (via programa simples de storage).
- **FR-003** — Medir o depósito de rent (lamports/SOL) necessário por tamanho de conta.
- **FR-004** — Fechar a conta e registrar o reembolso (confirma depósito reembolsável).
- **FR-005** — Registrar custo em USD (via preço SOL no momento) por byte/KB/MB/GB.

### Módulo B — State Compression (Merkle)
- **FR-006** — Criar Merkle tree (via `spl-account-compression`/Bubblegum).
- **FR-007** — Comprimir N itens de dados como leaves; registrar custo total e por leaf.
- **FR-008** — Medir custo por asset em função do tamanho da árvore (depth/canopy).

### Módulo C — Irys (permanente + term)
- **FR-009** — Publicar snapshot de dataset (JSON/Parquet) no Irys via wallet Solana.
- **FR-010** — Registrar custo de armazenamento permanente (USD/GB) e term storage.
- **FR-011** — Ler o dado de volta (retrieval) e verificar proof-of-existence.

### Módulo D — shdwDrive
- **FR-012** — Criar storage account e bucket (free 5GB + expansão).
- **FR-013** — Fazer upload de dados mutáveis; medir custo (US$ 0,05/GiB/ano) e latência.
- **FR-014** — Fazer download/leitura; medir latência e throughput.

### Módulo E — AWS Baseline (comparação)
- **FR-015** — Escrever o mesmo payload em S3 (Standard, IA, Glacier Deep Archive).
- **FR-016** — Registrar custo por GB/mês e latência de escrita/leitura de cada classe.

### Módulo F — Harness de Métricas (transversal)
- **FR-017** — Instrumentação unificada: cada operação emite `{layer, operation, payload_bytes, cost_sol, cost_usdc, cost_usd, latency_ms, throughput_mbps, timestamp}`.
- **FR-018** — Consolidar métricas em um único relatório JSON/CSV versionado.
- **FR-019** — Gerar **matriz de benchmark comparativa** Solana × AWS (custo + performance).

---

## 4. Requisitos Não-Funcionais (NFR-*)

- **NFR-001 (Reprodutibilidade):** todo benchmark deve ser re-executável via CLI, com payload determinístico e seed fixa.
- **NFR-002 (Custo transparente):** registrar custo em USD usando preço SOL/USDC no instante da operação, com timestamp.
- **NFR-003 (Performance):** medir latência (ms) e throughput (MB/s) de escrita e leitura em cada camada.
- **NFR-004 (Segurança):** chaves privadas em variáveis de ambiente / `.env` fora do git (`.gitignore`). Usar devnet para testes destrutivos.
- **NFR-005 (CLI First — Lei #1):** toda funcionalidade 100% via CLI antes de qualquer UI.
- **NFR-006 (Idempotência):** re-execução não duplica custo sem registrar (idempotent por operação + nonce).
- **NFR-007 (Testes):** cobertura ≥ 70% no harness e nas libs de storage.

---

## 5. Constraints (CON-*)

- **CON-001** — Usar **devnet** Solana para a maior parte (custo zero real); 1-2 operações em mainnet apenas para custo real, com orçamento máximo de ~0.1 SOL.
- **CON-002** — Stack de script: **TypeScript** (consistente com Passo 2 CDK) via `@solana/web3.js`, `@metaplex-foundation`, `@irys/sdk`, `@shadow-drive/sdk` (ou CLI oficial quando SDK imaturo).
- **CON-003** — Preço SOL/USDC coletado de fonte confiável (CoinGecko/Binance API) no momento do benchmark.
- **CON-004** — Sem deploy de infra AWS nova para o PoC (reuso do que já existe; baseline S3 pode ser local/scriptada).

---

## 6. User Stories (resumo — detalhadas nas stories)

| ID | User Story | Critério chave |
|----|-----------|----------------|
| 1.1 | Como dev, quero um ambiente Solana configurado para rodar os benchmarks via CLI. | Wallet + funding + `solana` CLI + script hello |
| 1.2 | Como dev, quero medir custo de armazenar bytes on-chain (rent). | FR-002..005 com custo/byte registrado |
| 1.3 | Como dev, quero medir custo de state compression (Merkle). | FR-006..008 |
| 1.4 | Como dev, quero medir custo do Irys (permanente + term). | FR-009..011 |
| 1.5 | Como dev, quero medir custo e latência do shdwDrive. | FR-012..014 |
| 1.6 | Como dev, quero uma baseline AWS S3 comparável. | FR-015..016 |
| 1.7 | Como dev, quero um harness de métricas unificado. | FR-017..018 |
| 1.8 | Como PO, quero a matriz de benchmark Solana × AWS. | FR-019 (relatório final) |

---

## 7. Critérios de Sucesso (Success Metrics)

- **Custo medido (não estimado)** para ≥ 4 camadas, em USD/GB, com fonte de preço timestampada.
- **Latência + throughput** medidos para escrita e leitura em cada camada.
- **Matriz comparativa** Solana × AWS com recomendação clara por caso de uso.
- **Reprodutível:** `npm run bench` regenera tudo do zero.
- **Entrega em ~4-5 dias** (PoC, não produto).

---

## 8. Riscos

| Risco | Prob. | Impacto | Mitigação |
|-------|-------|---------|-----------|
| SDK shdwDrive/Irys imaturo | Média | Alto | Usar CLI oficial como fallback |
| Custo mainnet variável | Alta | Médio | Devnet p/ volume; mainnet só 1-2 ops com teto de 0.1 SOL |
| Rate limit de RPC | Baixa | Médio | Backoff exponencial + cache |
| Preço SOL volátil | Alta | Médio | Registrar preço no instante + média móvel |

---

**Próximo:** @sm drafts stories 1.1–1.8 → @po valida → @architect define stack exato.
