# Benchmark Results — Armazenamento NATIVO Solana (PoC)

> **Gerado:** 2026-09-23 (execução operacional YOLO)  
> **Repo:** cesschneider/colosseum-hackathon · **PoC:** `poc/`  
> **Commit base:** `d77fc43` (7 stories implementadas, CI verde)

## ⚠️ Status da execução

| Passo | Status | Detalhe |
|-------|--------|---------|
| 1. Fundar wallet devnet | 🔴 Bloqueado | `solana airdrop` → **rate limit reached** (bloqueador externo). `devnet-pow mine` também rate-limitado. |
| 2. Deploy programa Anchor | 🟢 **Concluído** | `dataset_provenance.so` compilado + **deployed** em local validator (Agave 1.18.17). Pubkey `6nevEtv1X6KV8BprxJdD5qJSAPkdi2tym2zZPrvxeqF7`. |
| 3. Benchmarks (rent/compression/S3) | 🟢 Medido | Via **local validator** (`solana-test-validator` 1.18.17), não devnet. |
| 3. Benchmark programa (store/verify) | 🟢 **Medido** | `store_dataset` + `verify_dataset` executados on-chain com medição real. |
| 4. Docs | 🟢 Concluído | `docs/research/BENCHMARK-RESULTS.md` + `bench-results.csv` |

## 🌐 Rede usada

- **Local validator** (`http://localhost:8899`), **não devnet** — airdrop devnet rate-limitado (bloqueador externo).
- **SOL/USD:** `118.57` (CoinGecko, medido no momento da execução).
- **`lamports_per_byte` (rent-exempt):** `6960`.
- **Sem gasto de SOL real. Mainnet NÃO tocada.**

> ⚠️ **Nota de bloqueio (passo 1):** o airdrop devnet continua rate-limitado. Números abaixo são de **local validator**, não devnet.

---

## 📊 Números medidos

### 1. Rent (conta nativa, depósito rent-exempt)

Fórmula: `min_balance = (128 + data_size) × 6960 lamports`.

| data_size | min_balance (lamports) | cost (SOL) | cost (USD) | latência |
|-----------|------------------------|------------|------------|----------|
| 128 B     | 1 781 760              | 0.0017818  | $0.211      | 437 ms   |
| 1 KB      | 8 017 920              | 0.0080179  | $0.951      | 406 ms   |
| 10 KB     | 72 161 280             | 0.0721613  | $8.56       | 390 ms   |
| 100 KB    | 713 594 880            | 0.7135949  | $84.61      | 430 ms   |
| 1 MB      | 7 298 979 840          | 7.2989798  | $865.44     | 390 ms   |

**Conclusão:** armazenar 1 MB **diretamente em conta nativa** custa ~**7.30 SOL (~$865)** de depósito rent-exempt — proibitivo para dados. Rent é **reembolsável** ao fechar a conta (não aplicável neste caminho: conta System com dados só fecha via programa dono).

### 2. State Compression (Merkle tree, rent estimado via RPC)

| leaf_count | payload (bytes) | cost (SOL) | cost (USD) | cost/leaf (SOL) | latência |
|-----------|-----------------|------------|------------|-----------------|----------|
| 1 000     | 32 000          | 0.4461082  | $52.90     | 0.0004461       | 2 ms     |
| 10 000    | 320 000         | 4.4550682  | $528.24    | 0.0004455       | 3 ms     |
| 100 000   | 3 200 000       | 44.5446682 | $5281.66   | 0.0004454       | 1 ms     |

**Conclusão:** compression reduz o custo para ~**$0.00044/leaf** (praticamente linear), mas ainda caro em volume absoluto ($5.3k por 100k leaves). É a opção nativa mais econômica por registro.

### 3. Programa Anchor `dataset-provenance` (store/verify) — ✅ MEDIDO

Deploy + execução real on-chain em local validator (Agave 1.18.17).

| operação | record size | rent (SOL) | rent (USD) | fee (lamports) | latência |
|----------|-------------|------------|------------|----------------|----------|
| `store_dataset` | 353 B | 0.00334776 | $0.397 | 5000 | 282 ms |
| `verify_dataset` (match) | — | — | — | 5000 | 375 ms |
| `verify_dataset` (mismatch) | — | — | — | 5000 | 398 ms |

- **Record PDA:** `3gq844aCBXUwog7NMtdTY1AmukWXDESAxub4ezXBUb4Z` (dataset `bench-1790143994955`).
- **Programa:** `6nevEtv1X6KV8BprxJdD5qJSAPkdi2tym2zZPrvxeqF7` (`.so` 222 152 bytes, upgradeable BPFLoader).

**Conclusão:** um registro de provenance (hash 32B + metadados ~353B) custa **~0.0033 SOL (~$0.40)** de rent + **5000 lamports (~$0.0006)** de fee por escrita. Verificação read-only custa apenas a fee. **Ideal para o caso de uso provenance/token-gating.**

### 4. AWS S3 (baseline, PUT 1 MB real)

| storage class | payload | cost/mês (USD) | cost/ano (USD) | latência (PUT) |
|---------------|---------|----------------|----------------|----------------|
| STANDARD      | 1 MB    | $0.0000225     | $0.000270      | 1361 ms        |
| STANDARD_IA   | 1 MB    | $0.0000122     | $0.000146      | 229 ms         |
| DEEP_ARCHIVE  | 1 MB    | $0.00000097    | $0.0000116     | 290 ms         |

**Conclusão:** S3 é **ordens de magnitude mais barato** por byte (DEEP_ARCHIVE ≈ $0.00000097/MB/mês vs ~$865/MB de rent nativo).

---

## 🔍 Blocker técnico (superado no passo 2)

O build do programa falhava por **incompatibilidade de toolchain**. Resolução aplicada nesta execução:

1. **`/root/.cache` → exFAT** (symlink para `/media/cesar/SHARED/root_cache`), sem suporte a `chown`/symlinks → extração de `platform-tools` falhava. **Workaround:** bind-mount ext4 em `/root/.solana-cache-real`.
2. **`edition2024` em `constant_time_eq 0.4.2` (via `blake3`)** → pinou-se `blake3` para `1.5.0` (constant_time_eq `0.3.1`), sem edition2024.
3. **`Cargo.lock` v4** (regenerado pelo host cargo 1.98.1) → revertido para v3 (compatível com platform-tools cargo 1.75).
4. **`proc-macro2::Span::source_file()`** faltando → adicionada dependência `proc-macro2` com feature `span-locations`.
5. **Validator Agave 4.2.2 rodando vs `.so` SBFv1** → reiniciado `solana-test-validator` com binário **1.18.17** (alinhado ao platform-tools v1.41).

Build do `.so` bem-sucedido via `cargo build-sbf` (platform-tools v1.41) e deploy via `solana program deploy`.

---

## 🧪 Quality gates (re-verificados após correções)

- `npm run lint` ✅
- `npm run typecheck` ✅
- `npm test` ✅ **20/20 passing** (5 suites)
- **Correção operacional:** `src/bench/rent.ts` — remoção do fechamento inválido de conta System com dados.

## 📁 Artefatos

- **`poc/docs/research/BENCHMARK-RESULTS.md`** — este relatório.
- **`poc/bench-results.csv`** — métricas em CSV normalizado.
- **`poc/docs/research/bench-results.raw.json`** — dados brutos (rent/compression/S3).
- **`poc/docs/research/program-benchmark.json`** — medição do programa store/verify.
- **`poc/scripts/run-program-benchmark.ts`** — runner do programa (store/verify).
- **`poc/.deploy/progress.json`** — estado do runbook operacional.

---

## 🔑 Conclusão estratégica

Para o **marketplace de dados públicos MICRO BR** (produto do Colosseum):

- **Armazenamento de conteúdo (bytes) NÃO deve ir nativo na Solana** — rent nativo (~$865/MB) é inviável.
- **Solana nativo é ideal para `provenance`/`token-gating`** — um registro (hash + metadados ~353B) custa ~$0.40 de rent + fee mínima. **Programa `dataset-provenance` deployed e funcional (store/verify medidos).**
- **Conteúdo → AWS S3** (baseline medido). **Provenance → Solana** (programa Anchor). Alinhado com a decisão de arquitetura "Solana = provenance/token-gating, storage = AWS".
