# PRD — Epic 1: PoC de Armazenamento de Dados NATIVO Solana (com Métricas de Custo & Performance)

**Projeto:** Hackathon Colosseum 2026
**Autor:** @pm (Morgan)
**Data:** 22 Set 2026
**Status:** Draft → (aguardando validação @po)
**Base técnico:** `docs/research/ARMAZENAMENTO-DESCENTRALIZADO-SOLANA.md`, `DECISAO-PLACEMENT-SOLANA-VS-AWS.md`

---

## 0. Constraint HARD (decisão do time)

> **CON-000 — Somente tecnologias NATIVAS Solana.** Nenhuma tecnologia cross-chain ou de outra rede (Sui/Walrus, Irys-L1, Arweave, Filecoin, IPFS) é aceita no PoC. Qualquer storage descentralizado que não rode na Solana está **fora de escopo**.

**Implicação (descoberta durante a pesquisa):** não existe storage "quente"/mutável nativo Solana ativo (shdwDrive abandonado; Irys virou Layer-1 própria). Portanto o PoC nativo Solana cobre exatamente 3 camadas:

1. **On-chain (rent)** — armazenar bytes em contas Solana.
2. **State compression (Merkle/Bubblegum)** — comprimir dados em árvore Merkle.
3. **Programa próprio (custom program)** — smart contract Solana para armazenar/ler dados e expor metadados/provenance.

**Tudo que é "storage de volume" fica na AWS** (já documentado no placement). Solana nativo entra como **camada de provenance, integridade e token-gating**, não como storage de big data.

---

## 1. Visão

Validar **empiricamente** o custo e a performance das **3 camadas nativas de armazenamento Solana** (rent, compression, program próprio), medindo custo real por byte/asset e latência/throughput — e comparando contra a baseline AWS S3, para fechar com números a decisão de placement.

**Objetivo:** responder com dados medidos:
- Quanto custa de verdade armazenar 1 KB / 1 MB / 1 GB on-chain (rent)?
- Qual o custo por asset em state compression (em função do tamanho da árvore)?
- Qual a latência e o custo de um programa próprio de storage/provenance?
- Onde Solana nativo ganha e onde perde contra AWS?

---

## 2. Escopo (In / Out)

### IN Scope
- **Solana on-chain (rent):** escrever payload de N bytes em contas, medir depósito/byte, fechar e verificar reembolso.
- **Solana state compression (Merkle/Bubblegum):** criar árvore, comprimir N leaves, medir custo por leaf × depth/canopy.
- **Programa próprio (custom on-chain program):** um programa mínimo de storage + provenance (armazena hash/metadados de dataset), medir custo de deploy + custo por operação.
- **AWS baseline:** S3 (Standard, IA, Glacier Deep Archive) — para comparação 1:1 (a AWS é aceita como baseline, não como parte do produto blockchain).
- **Harness de métricas:** coleta unificada de custo (SOL gasto, USD equivalente) e performance (latência, throughput, tamanho).

### OUT of Scope (Fase 1)
- Qualquer storage cross-chain (Walrus/Sui, Irys-L1, Arweave, Filecoin, IPFS) — **CON-000**.
- Token-gating / pagamento por acesso (Fase 3).
- Frontend/dashboard (Fase 2).
- ETL completo dos datasets (Passo 2 do MVP de dados, epics separados).

---

## 3. Requisitos Funcionais (FR-*)

### Módulo A — Solana On-Chain (rent)
- **FR-001** — Criar wallet Solana em devnet (e 1-2 ops em mainnet com teto de custo).
- **FR-002** — Escrever payload de N bytes (128B, 1KB, 10KB, 100KB, 1MB) em uma conta.
- **FR-003** — Medir o depósito de rent (`min_balance` = (128 + data_size) × lamports/byte).
- **FR-004** — Fechar a conta e registrar o reembolso (confirma depósito reembolsável).
- **FR-005** — Registrar custo em USD (preço SOL timestampado) por byte/KB/MB/GB.

### Módulo B — State Compression (Merkle)
- **FR-006** — Criar Merkle tree (spl-account-compression / Bubblegum) com depth/canopy configurável.
- **FR-007** — Comprimir N leaves (1k, 10k, 100k) com payload determinístico.
- **FR-008** — Medir custo total da árvore e custo por leaf, × depth/canopy.

### Módulo C — Programa Próprio (Storage + Provenance)
- **FR-009** — Deploy de um programa Solana mínimo (Anchor ou Rust nativo) que armazena hash/metadados de dataset.
- **FR-010** — Medir custo de deploy (rent do program account) e custo por operação (write/update/read).
- **FR-011** — Expor função de verificação de integridade (dado hash → confirma on-chain).

### Módulo D — AWS Baseline (comparação)
- **FR-012** — Escrever o mesmo payload em S3 (Standard, IA, Glacier Deep Archive).
- **FR-013** — Registrar custo por GB/mês e latência de escrita/leitura de cada classe.

### Módulo E — Harness de Métricas (transversal)
- **FR-014** — Instrumentação unificada: `{layer, operation, payload_bytes, cost_sol, cost_usd, latency_ms, throughput_mbps, timestamp}`.
- **FR-015** — Consolidar métricas em relatório JSON/CSV versionado.
- **FR-016** — Gerar **matriz de benchmark comparativa** Solana-nativo × AWS.

---

## 4. Requisitos Não-Funcionais (NFR-*)

- **NFR-001 (Reprodutibilidade):** todo benchmark re-executável via CLI, payload determinístico.
- **NFR-002 (Custo transparente):** custo em USD com preço SOL timestampado no instante da operação.
- **NFR-003 (Performance):** latência (ms) e throughput (MB/s) de escrita e leitura.
- **NFR-004 (Segurança):** chaves privadas em `.env` fora do git; devnet para volume.
- **NFR-005 (CLI First — Lei #1):** tudo via CLI.
- **NFR-006 (Idempotência):** re-execução não duplica custo sem registro.
- **NFR-007 (Testes):** cobertura ≥ 70% no harness e nas libs.

---

## 5. Constraints (CON-*)

- **CON-000** — Somente nativo Solana (sem cross-chain). **HARD.**
- **CON-001** — Devnet para volume; mainnet só 1-2 ops com teto ~0.1 SOL.
- **CON-002** — Stack: **TypeScript** (`@solana/web3.js`, `@metaplex-foundation/js`) + **Anchor/Rust** para o programa próprio.
- **CON-003** — Preço SOL/USDC de fonte confiável (CoinGecko/Binance) no momento do benchmark.
- **CON-004** — Sem deploy de infra AWS nova; baseline S3 reusa credenciais existentes.

---

## 6. User Stories (resumo)

| ID | User Story | Critério chave |
|----|-----------|----------------|
| 1.1 | Ambiente Solana + harness base (CLI). | wallet + funding + `npm run hello` |
| 1.2 | Benchmark on-chain (rent). | FR-002..005 com custo/byte |
| 1.3 | Benchmark state compression (Merkle). | FR-006..008 |
| 1.4 | Programa próprio de storage/provenance. | FR-009..011 |
| 1.5 | Baseline AWS S3. | FR-012..013 |
| 1.6 | Harness de métricas unificado. | FR-014..015 |
| 1.7 | Matriz comparativa (relatório final). | FR-016 |

---

## 7. Critérios de Sucesso

- **Custo medido (não estimado)** para as 3 camadas nativas Solana, em USD/byte e USD/asset.
- **Latência + throughput** medidos para escrita e leitura.
- **Matriz comparativa** Solana-nativo × AWS com recomendação clara por caso de uso.
- **Reprodutível:** `npm run bench` regenera tudo.
- **Entrega em ~3-4 dias** (PoC reduzido a nativo Solana).

---

## 8. Riscos

| Risco | Prob. | Impacto | Mitigação |
|-------|-------|---------|-----------|
| Programa próprio (Rust/Anchor) tem curva | Média | Médio | Começar com exemplo mínimo; Cesar domina Rust |
| Custo mainnet variável | Alta | Médio | Devnet p/ volume; mainnet teto 0.1 SOL |
| Rate limit RPC | Baixa | Médio | Backoff exponencial + cache |
| Preço SOL volátil | Alta | Médio | Registrar no instante + média móvel |
| Limite 10 MiB/conta | Alto (1MB) | Médio | Fracionar payload em contas menores; documentar |

---

**Próximo:** @sm re-drafts stories 1.1–1.7 → @po valida → @architect define programa Rust exato.
