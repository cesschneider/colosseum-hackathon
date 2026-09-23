# STORY 1.2 — Benchmark On-Chain (Rent)

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento NATIVO Solana)
**Agente:** @dev (Dex)

## Descrição
Medir o custo real de armazenar bytes diretamente em contas Solana (rent) e o reembolso ao fechar a conta.

## Critérios de Aceitação
- [ ] Escrever payload de N bytes (128B, 1KB, 10KB, 100KB, 1MB) em uma conta (ou contas fracionadas, dado o limite de 10 MiB).
- [ ] Capturar `min_balance` (rent-exempt) por tamanho → calcular `lamports/byte` efetivo.
- [ ] Converter custo para USD usando preço SOL timestampado.
- [ ] Fechar a conta e registrar o reembolso (delta deposit/refund).
- [ ] Registrar métricas no schema unificado (FR-014).

## Notas Técnicas
- Fórmula: `min_balance = (128 + data_size) × lamports_per_byte` (pós SIMD-0437).
- Limite por conta: 10 MiB; para 1MB usar conta grande (rent alto).

## Dependências
- DEP-002: STORY 1.1.

## Estimativa
~0.5 dia
