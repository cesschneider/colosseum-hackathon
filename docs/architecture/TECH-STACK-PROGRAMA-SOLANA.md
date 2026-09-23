# Arquitetura — PoC de Armazenamento NATIVO Solana (Epic 1)

**Projeto:** Hackathon Colosseum 2026
**Autor:** @architect (Aria)
**Data:** 22 Set 2026
**Constraint:** CON-000 — somente tecnologias nativas Solana (sem cross-chain).

---

## 1. Tech Stack (Decisões + Rejeições)

| Camada | Escolha | Rationale | Rejeitado |
|--------|---------|-----------|-----------|
| Linguagem de script | **TypeScript** | Consistente com o Passo 2 (CDK); SDK maduro | Python (web3.py menos maduro) |
| SDK blockchain | **@solana/web3.js** | Oficial, estável | — |
| Framework de programa | **Anchor 0.30** | Abstrai contas/IDL; mais rápido que Rust puro | Rust nativo (verboso p/ PoC) |
| Compressão | **@solana/spl-account-compression** + Metaplex Bubblegum | Padrão para Merkle trees | — |
| Preço SOL | CoinGecko API (gratuita) | Simples, sem key | Binance (requer auth) |
| Baseline AWS | AWS SDK v3 (S3) | Reuso de credenciais CDK | — |

**Rejeições explícitas:**
- ~~shdwDrive~~ — abandonado.
- ~~Irys~~ — virou Layer-1 própria (não Solana).
- ~~Walrus~~ — Sui (cross-chain).
- ~~Arweave/Filecoin/IPFS~~ — não nativos Solana (CON-000).

---

## 2. Programa Próprio (Anchor/Rust) — O Componente Central

O programa é o coração do PoC: ele faz **provenance de datasets** (armazena hash + metadados on-chain e expõe verificação de integridade). É o que o produto final usa para provar que um dataset é autêntico.

### 2.1 Contas (Account Structure)

```rust
#[account]
pub struct DatasetRecord {
    pub owner: Pubkey,          // quem registrou o dataset
    pub dataset_id: String,     // slug (ex: "ipca", "anp-combustivel")
    pub content_hash: [u8; 32], // SHA-256 do arquivo Parquet
    pub source: String,         // fonte (IBGE, ANP, WorldBank)
    pub license: String,        // licença de redistribuição
    pub schema_version: u32,    // versão do schema do dataset
    pub timestamp: i64,         // quando foi registrado
    pub bump: u8,               // PDA bump seed
}
```

### 2.2 Instruções (Instructions)

| Instrução | Argumentos | Custo estimado | Descrição |
|-----------|-----------|----------------|-----------|
| `initialize` | — | ~1 SOL deploy | Cria a conta de configuração do programa |
| `store_dataset` | dataset_id, content_hash, source, license, schema_version | ~0.000005 SOL tx + rent | Registra/atualiza hash de um dataset (PDA por dataset_id) |
| `verify_dataset` | dataset_id, content_hash | ~0.000005 SOL tx (read) | Confirma se o hash bate com o on-chain |
| `update_dataset` | dataset_id, new_content_hash | ~0.000005 SOL tx | Atualiza o hash (novo snapshot) |

### 2.3 PDA (Program Derived Address)

- `DatasetRecord` PDA: `seeds = [b"dataset", dataset_id.as_bytes()]` → endereço determinístico por dataset.
- Permite verificação sem consultar indexador externo.

### 2.4 Fluxo de Provenance (end-to-end)

```
Lambda Ingest (AWS)
  → gera Parquet em S3
  → calcula SHA-256 do arquivo
  → chama store_dataset(hash, metadados) no programa Solana (via wallet do time)
  → PDA gravado on-chain

Cliente (qualquer um)
  → baixa dataset da API (S3)
  → calcula SHA-256 local
  → chama verify_dataset(id, hash) on-chain (read-only, grátis)
  → se true → dado autêntico, não adulterado
```

---

## 3. Estrutura de Pastas do PoC

```
colosseum-hackathon/
├── poc/
│   ├── package.json           # deps TS + scripts
│   ├── .env.example           # PRIVATE_KEY, RPC, AWS creds
│   ├── src/
│   │   ├── harness/
│   │   │   ├── metrics.ts     # recordMetric() (FR-014)
│   │   │   └── price.ts       # SOL→USD (CoinGecko)
│   │   ├── bench/
│   │   │   ├── rent.ts        # STORY 1.2
│   │   │   ├── compression.ts  # STORY 1.3
│   │   │   ├── program.ts     # STORY 1.4 (deploy + store/verify)
│   │   │   └── s3.ts          # STORY 1.5
│   │   └── cli.ts             # npm run bench entrypoint
│   ├── programs/
│   │   └── dataset-provenance/
│   │       ├── Cargo.toml
│   │       └── src/lib.rs     # programa Anchor
│   ├── Anchor.toml
│   └── tests/
│       └── provenance.test.ts # cobertura ≥ 70%
├── bench-results.json         # saída versionada
└── bench-results.csv
```

---

## 4. Schema de Métricas (FR-014)

```typescript
interface Metric {
  layer: "solana-rent" | "solana-compression" | "solana-program" | "aws-s3";
  operation: "write" | "read" | "deploy" | "verify" | "close";
  payload_bytes: number;
  cost_sol: number;      // lamports→SOL (0 se n/a)
  cost_usd: number;      // preço SOL timestampado
  latency_ms: number;
  throughput_mbps: number;
  timestamp: string;     // ISO 8601
}
```

---

## 5. Decisões de Design Chave

1. **Programa próprio > usar uma lib externa** — é o único componente nativo Solana que entrega *provenance verificável* (a lib de compression só faz hash em árvore, não expõe verify por dataset).
2. **PDA determinístico por dataset_id** — permite lookup O(1) sem indexador.
3. **Hash SHA-256 (32 bytes) on-chain** — custo mínimo de rent; o dado completo fica no S3, nunca on-chain.
4. **Devnet primeiro** — todo o benchmark roda em devnet (custo zero real); mainnet só 1-2 ops de smoke test com teto 0.1 SOL.

---

## 6. Custo Estimado (pré-benchmark, será medido)

| Operação | Custo estimado |
|----------|----------------|
| Deploy do programa | ~0.5–1 SOL (rent do program account, ~10KB) |
| store_dataset | ~0.000005 SOL (tx) + ~0.001 SOL (rent PDA ~100 bytes) |
| verify_dataset | ~0.000005 SOL (read-only, sem rent) |
| Compression (1M leaves) | ~5.3 SOL (árvore) ≈ 0.000005 SOL/leaf |

**Hipótese a validar:** custo de provenance on-chain é **desprezível** (< US$ 0.01/dataset) comparado ao custo de storage na AWS — reforçando a tese de placement.

---

**Próximo:** @po valida stories → @dev implementa Batch 1 (1.1 + 1.6).
