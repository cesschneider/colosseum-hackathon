# Runbook — Execução do PoC (Fase 1) + Deploy AWS

**Data:** 23 set 2026
**Estado:** código 100% implementado, CI verde, branch protection ativa. Restam os passos operacionais abaixo.

---

## Estado Atual (commit `d77fc43`)

- ✅ Código de todas as 7 stories implementado (`poc/`)
- ✅ 20 testes Jest + 1 teste Rust, cobertura 86.88% (TS)
- ✅ CI verde: TypeScript Tests & Coverage, Rust Tests, Lint & Type Check
- ✅ Branch protection em `master` (3 status checks obrigatórios, sem review)
- ✅ Toolchain: Node 20, Rust 1.98, Solana CLI 4.2.2, Anchor 1.2.0
- ✅ Programa Anchor compila + clippy + fmt limpos
- ✅ Programa pubkey: `6nevEtv1X6KV8BprxJdD5qJSAPkdi2tym2zZPrvxeqF7`

---

## Passos Operacionais Restantes (para "testar amanhã")

### 1. Obter SOL devnet
Airdrop está rate-limited. Caminhos (em ordem):
1. `solana airdrop 2 --url devnet` (retry; funciona após janela)
2. PoW faucet: `devnet-pow mine -d 3 --reward 0.02 --no-infer -t 5000000000`
3. `solana-test-validator` (local, SOL ilimitado — bom p/ smoke test offline)

### 2. Deploy do programa Anchor (Story 1.4)
```bash
cd /root/projects/colosseum-hackathon/poc
export PATH="$HOME/.cargo/bin:$PATH:$HOME/.local/share/solana/install/active_release/bin"
anchor build
anchor deploy --provider.cluster devnet
```

### 3. Executar benchmarks (Stories 1.2, 1.3, 1.5)
```bash
npm run bench   # rent + compression + program + s3
```

### 4. Baseline AWS S3 (Story 1.5)
Usa credenciais `eworks-dev` (account 666637312477) + `AWS_PROFILE=eworks-dev`.

### 5. Gerar matriz comparativa (Story 1.7)
`docs/research/BENCHMARK-RESULTS.md` + `bench-results.csv`.

### 6. Deploy CDK (decisão do usuário: infra nova S3 + Lambda)
```bash
# infra/ em separado, CDK TypeScript
cdk deploy --profile eworks-dev
```

---

## Decisões Travadas (23 set)

1. **Devnet** (custo zero; números aproximados)
2. **Auto-merge YOLO** (CI gates verdes, sem review humano)
3. **Deploy CDK** (S3 bucket + Lambda) antes do benchmark

## Bloqueadores Conhecidos

- **Airdrop rate-limit** → usar PoW faucet (`devnet-pow`) ou `solana-test-validator`.
- **Mainnet** exige SOL real + wallet do Cesar (manual amanhã).

---

## Wallets / Pubkeys (devnet)

- **Bench wallet:** `5vgEPFEkc3MF19rpExVfZnmfv6EYkATYWdxAJ6D8HYsE`
  - keypair: `poc/.deploy/bench-wallet.json` (gitignored)
- **Programa:** `6nevEtv1X6KV8BprxJdD5qJSAPkdi2tym2zZPrvxeqF7`
  - keypair: `poc/.deploy/dataset_provenance-keypair.json` (gitignored)
