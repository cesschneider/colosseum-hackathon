# STORY 1.2 — Benchmark On-Chain (Rent)

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento Solana)
**Agente:** @dev (Dex)

## Descrição
Medir o custo real de armazenar bytes diretamente em contas Solana (rent) e o reembolso ao fechar a conta.

## Critérios de Aceitação
- [ ] Programa/storage que escreve payload de N bytes (128B, 1KB, 10KB, 100KB, 1MB) em uma conta.
- [ ] Capturar `min_balance` (rent-exempt) por tamanho → calcular `lamports/byte` efetivo.
- [ ] Converter custo para USD usando preço SOL no instante (com timestamp).
- [ ] Fechar a conta e registrar o reembolso (delta entre deposit e refund).
- [ ] Registrar métricas no schema unificado (FR-017).

## Notas Técnicas
- Fórmula: `min_balance = (128 + data_size) × lamports_per_byte` (atual pós SIMD-0437).
- Limite por conta: 10 MiB. Para 1MB precisa de conta grande (rent alto).
- Usar `getMinimumBalanceForRentExemption` RPC.

## Dependências
- DEP-002: STORY 1.1 (ambiente).

## Estimativa
~0.5 dia
