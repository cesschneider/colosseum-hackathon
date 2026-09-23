# STORY 1.4 — Programa Próprio de Storage + Provenance (Rust/Anchor)

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento NATIVO Solana)
**Agente:** @dev (Dex)

## Descrição
Criar um programa Solana mínimo (Anchor/Rust nativo) que armazena hash + metadados de dataset e expõe verificação de integridade. Medir custo de deploy e por operação.

## Critérios de Aceitação
- [ ] Programa Anchor com instruções: `store_dataset` (hash + metadados), `verify_dataset` (dado → confirma hash), `update_dataset`.
- [ ] Deploy em devnet e medir custo do program account (rent).
- [ ] Medir custo por operação (write/update/read) em SOL + USD.
- [ ] Registrar métricas no schema unificado (`layer = "solana-program"`).

## Notas Técnicas
- Anchor é o caminho mais rápido; Cesar domina Rust.
- Este é o componente que efetivamente faz "provenance" no produto final (hash on-chain).
- Lei #1: CLI primeiro (`npm run program:deploy`, `npm run program:store`).

## Dependências
- DEP-002: STORY 1.1.

## Estimativa
~1 dia (curva Rust/Anchor)
