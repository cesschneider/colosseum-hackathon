# STORY 1.4 — Benchmark Irys (Permanente + Term)

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento Solana)
**Agente:** @dev (Dex)

## Descrição
Publicar snapshot de dataset no Irys (via wallet Solana) e medir custo de storage permanente vs term, com prova de existência e retrieval.

## Critérios de Aceitação
- [ ] Conectar Irys SDK com wallet Solana (devnet Irys).
- [ ] Publicar payload (100KB, 1MB, 10MB) em storage permanente e term.
- [ ] Registrar custo USD/GB (ref ~US$ 2,33/GB permanente).
- [ ] Ler de volta e verificar proof-of-existence (hash).

## Notas Técnicas
- Irys uploads < 100KiB são gratuitos (usar p/ smoke test).
- Custo permanente ref: US$ 2,33/GB; term ~US$ 0,00007358/GB/epoch.

## Dependências
- DEP-002: STORY 1.1.

## Estimativa
~0.5 dia
