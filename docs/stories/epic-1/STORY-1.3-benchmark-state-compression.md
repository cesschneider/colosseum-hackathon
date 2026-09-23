# STORY 1.3 — Benchmark State Compression (Merkle)

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento NATIVO Solana)
**Agente:** @dev (Dex)

## Descrição
Medir o custo de comprimir dados via Merkle tree (state compression) e o custo por leaf em função do tamanho da árvore.

## Critérios de Aceitação
- [ ] Criar Merkle tree (spl-account-compression / Bubblegum) com depth configurável.
- [ ] Comprimir N leaves (1k, 10k, 100k) com payload determinístico.
- [ ] Registrar custo total da árvore (rent) e custo por leaf.
- [ ] Tabela de custo por leaf × depth/canopy.

## Notas Técnicas
- Referência Metaplex: 1M cNFTs ≈ 5.3 SOL (~0.000005 SOL/asset).
- Dado bruto vai em transação; só hash na árvore. Útil p/ integridade em escala.

## Dependências
- DEP-002: STORY 1.1.

## Estimativa
~0.5 dia
