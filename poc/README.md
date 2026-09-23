# PoC — Armazenamento NATIVO Solana (Epic 1)

Valida empiricamente custo + performance de armazenamento **nativo Solana** (rent, state compression, programa próprio) contra baseline AWS S3.

## Estrutura

```
poc/
├── src/
│   ├── harness/           # métricas (FR-014) + preço SOL
│   ├── bench/             # rent, compression, s3 + models puros
│   └── cli.ts             # npm run hello / bench
├── programs/dataset-provenance/   # programa Anchor (provenance)
├── tests/                 # Jest (TS)
└── Anchor.toml
```

## Comandos

```bash
npm install
npm test            # 20 testes
npm run test:coverage # cobertura ≥ 70%
npm run typecheck
npm run lint
npm run hello       # valida conectividade Solana devnet
npm run bench       # executa benchmarks de rede
```

Programa Rust (provenance):
```bash
cd programs/dataset-provenance
cargo build && cargo test && cargo clippy -- -D warnings && cargo fmt --check
```

## Programa Próprio (dataset-provenance)

- **Pubkey:** `6nevEtv1X6KV8BprxJdD5qJSAPkdi2tym2zZPrvxeqF7`
- **Instruções:** `store_dataset`, `update_dataset`, `verify_dataset`
- **PDA:** `seeds = [b"dataset", dataset_id]`
- **Keypair do programa (deploy/upgrade):** `poc/.deploy/dataset_provenance-keypair.json` (gitignored)

## Rede

- **Devnet** (custo zero). RPC: `https://api.devnet.solana.com`
- Config de rede/keys em `.env` (ver `.env.example`).

## Métricas (schema)

```typescript
{ layer, operation, payload_bytes, cost_sol, cost_usd, latency_ms, throughput_mbps, timestamp }
```
