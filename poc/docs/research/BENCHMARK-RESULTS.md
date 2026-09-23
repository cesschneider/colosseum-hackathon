# Benchmark Results — Armazenamento NATIVO Solana (PoC)

> **Gerado:** 2026-09-23 (execução operacional YOLO)  
> **Repo:** cesschneider/colosseum-hackathon · **PoC:** `poc/`  
> **Commit base:** `d77fc43` (7 stories implementadas, CI verde)

## ⚠️ Status da execução

| Passo | Status | Detalhe |
|-------|--------|---------|
| 1. Fundar wallet devnet | 🔴 Bloqueado | `solana airdrop` → **rate limit reached** (bloqueador externo) |
| 2. Deploy programa Anchor | 🔴 Bloqueado | `anchor build` falha: toolchain platform-tools incompatível (ver §Blocker) |
| 3. Benchmarks (rent/compression/S3) | 🟢 Medido | Via **local validator** (`solana-test-validator`), não devnet |
| 3. Benchmark programa (store/verify) | 🔴 Bloqueado | Depende do `.so` (passo 2) |
| 4. Docs | 🟢 Concluído | `docs/research/BENCHMARK-RESULTS.md` + `bench-results.csv` |

## 🌐 Rede usada

- **Local validator** (`http://localhost:8899`), **não devnet** — airdrop devnet rate-limitado.
- **SOL/USD:** `119.61` (CoinGecko, medido no momento da execução).
- **`lamports_per_byte` (rent-exempt):** `6960`.
- **Sem gasto de SOL real. Mainnet NÃO tocada.**

---

## 📊 Números medidos

### 1. Rent (conta nativa, depósito rent-exempt)

Fórmula: `min_balance = (128 + data_size) × 6960 lamports`.

| data_size | min_balance (lamports) | cost (SOL) | cost (USD) | latência |
|-----------|------------------------|------------|------------|----------|
| 128 B     | 1 781 760              | 0.0017818  | $0.213      | 102 ms   |
| 1 KB      | 8 017 920              | 0.0080179  | $0.959      | 439 ms   |
| 10 KB     | 72 161 280             | 0.0721613  | $8.63       | 417 ms   |
| 100 KB    | 713 594 880            | 0.7135949  | $85.35      | 418 ms   |
| 1 MB      | 7 298 979 840          | 7.2989798  | $873.03     | 418 ms   |

**Conclusão:** armazenar 1 MB **diretamente em conta nativa** custa ~**7.30 SOL (~$873)** de depósito rent-exempt — proibitivo para dados. Rent é **reembolsável** ao fechar a conta (não aplicável neste caminho: conta System com dados só fecha via programa dono).

### 2. State Compression (Merkle tree, rent estimado via RPC)

| leaf_count | payload (bytes) | cost (SOL) | cost (USD) | cost/leaf (SOL) | latência |
|-----------|-----------------|------------|------------|-----------------|----------|
| 1 000     | 32 000          | 0.4461082  | $53.36     | 0.0004461       | 2 ms     |
| 10 000    | 320 000         | 4.4550682  | $532.87    | 0.0004455       | 2 ms     |
| 100 000   | 3 200 000       | 44.5446682 | $5327.99   | 0.0004454       | 2 ms     |

**Conclusão:** compression reduz o custo para ~**$0.00044/leaf** (praticamente linear), mas ainda caro em volume absoluto ($5.3k por 100k leaves). É a opção nativa mais econômica por registro.

### 3. AWS S3 (baseline, PUT 1 MB real)

| storage class | payload | cost/mês (USD) | cost/ano (USD) | latência (PUT) |
|---------------|---------|----------------|----------------|----------------|
| STANDARD      | 1 MB    | $0.0000225     | $0.000270      | 1514 ms        |
| STANDARD_IA   | 1 MB    | $0.0000122     | $0.000146      | 220 ms         |
| DEEP_ARCHIVE  | 1 MB    | $0.00000097    | $0.0000116     | 234 ms         |

**Conclusão:** S3 é **ordens de magnitude mais barato** por byte (DEEP_ARCHIVE ≈ $0.00000097/MB/mês vs ~$873/MB de rent nativo).

### 4. Programa Anchor (store/verify)

- **Status:** ❌ **não executado (bloqueado)** — o `.so` não compilou; dependência do passo 2.

---

## 🔍 Blocker técnico (passo 2 — deploy Anchor)

O build do programa falha por **incompatibilidade de toolchain** no ambiente, não por bug do código:

1. **`/root/.cache` → exFAT** (symlink para `/media/cesar/SHARED/root_cache`), sem suporte a `chown`/symlinks → a extração de `platform-tools` do `cargo-build-sbf` falha (`Cannot change ownership ... Operation not permitted`).
   - **Workaround aplicado:** bind-mount de dir ext4 em `/root/.solana-cache-real` sobre `/media/cesar/SHARED/root_cache/solana`. ✅ Extração OK.
2. **Toolchain v1.41** (usada pelo solana-cli 1.18.17): cargo 1.75 **não aceita `edition2024`** (dependência transitiva `constant_time_eq 0.4.2` via `blake3`).
3. **Toolchain v1.57** (cargo 1.95): aceita edition2024, mas **renomeou** `sbf-solana-solana` → `sbpf-solana-solana` (symlink de compat criado ✅), e ainda há erros de lang-item/target-triple (`None` lang_item, `Copy` not found) ao compilar deps antigas como `typenum`.

**Resolução recomendada:** alinhar `solana-cli`/`agave-validator` para a versão compatível com platform-tools v1.57 (Agave 2.x), OU pinar `blake3` para versão sem `edition2024`. Fora do escopo da execução operacional (não é código novo das stories).

---

## 🧪 Quality gates (re-verificados após correções)

- `npm run lint` ✅
- `npm run typecheck` ✅
- `npm test` ✅ **20/20 passing** (5 suites)
- **Correção operacional aplicada:** `src/bench/rent.ts` — remoção do fechamento de conta inválido (System account com dados não fecha por transfer); agora registra o depósito rent-exempt medido com `refundedLamports: 0` documentado.

## 📁 Artefatos

- **`poc/docs/research/BENCHMARK-RESULTS.md`** — este relatório.
- **`poc/bench-results.csv`** — métricas em CSV normalizado.
- **`poc/docs/research/bench-results.raw.json`** — dados brutos (schema completo).
- **`poc/.deploy/progress.json`** — estado do runbook operacional.
- **`poc/scripts/run-benchmarks.ts`** — runner operacional (invoca os benchmarks existentes das stories).

---

## 🔑 Conclusão estratégica

Para o **marketplace de dados públicos MICRO BR** (produto do Colosseum):

- **Armazenamento de conteúdo (bytes) NÃO deve ir nativo na Solana** — rent nativo (~$873/MB) é inviável.
- **Solana nativo é ideal para `provenance`/`token-gating`** (hash + metadados, ~centenas de bytes por registro), como projetado no programa `dataset-provenance`.
- **Conteúdo → AWS S3** (baseline medido). **Provenance → Solana** (programa Anchor). Alinhado com a decisão de arquitetura "Solana = provenance/token-gating, storage = AWS".
