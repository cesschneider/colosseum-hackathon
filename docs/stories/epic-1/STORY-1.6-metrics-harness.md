# STORY 1.6 — Harness de Métricas Unificado

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento NATIVO Solana)
**Agente:** @dev (Dex)

## Descrição
Implementar o harness de coleta unificada de métricas (custo + performance) e consolidar tudo em relatório versionado.

## Critérios de Aceitação
- [ ] Schema: `{layer, operation, payload_bytes, cost_sol, cost_usd, latency_ms, throughput_mbps, timestamp}`.
- [ ] Helper `recordMetric()` usado por todas as stories (FR-014).
- [ ] Consolidar em `bench-results.json` + `bench-results.csv` versionados.
- [ ] Conversor SOL→USD com preço timestampado (CoinGecko/Binance).
- [ ] `npm run bench` executa todos os benchmarks e regenera o relatório.
- [ ] Testes do harness com cobertura ≥ 70%.

## Notas Técnicas
- Preço SOL: `https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd`.
- Idempotência por nonce/timestamp.

## Dependências
- DEP-002: STORY 1.1.

## Estimativa
~0.5 dia
