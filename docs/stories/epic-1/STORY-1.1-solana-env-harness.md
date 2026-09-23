# STORY 1.1 — Ambiente Solana + Harness Base (CLI)

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento Solana)
**Agente:** @sm (River) / @dev (Dex)

## Descrição
Configurar o ambiente Solana (devnet), wallet com funding, CLI oficial, e a estrutura base do projeto de benchmark (TypeScript) com um comando `hello` que valida conectividade end-to-end.

## Critérios de Aceitação
- [ ] Projeto TypeScript inicializado (`package.json`, `tsconfig`, `.gitignore` com `.env`).
- [ ] Dependências instaladas: `@solana/web3.js`, `@project-serum/anchor` (ou só web3), `@irys/sdk`, `@shadow-drive/sdk` (ou CLI), `@metaplex-foundation/js`.
- [ ] Wallet Solana criada em **devnet** com funding (airdrop ≥ 1 SOL).
- [ ] `solana` CLI funcional (`solana balance` retorna saldo devnet).
- [ ] Comando `npm run hello` faz 1 transação trivial (airdrop/transfer) e imprime saldo + latência.
- [ ] `.env` configurado com chaves (fora do git); `.env.example` documentado.

## Notas Técnicas
- Devnet endpoint: `https://api.devnet.solana.com`.
- Nunca commitar chave privada. Usar `keypair` file ou `PRIVATE_KEY` em `.env`.
- Lei #1 (CLI First): tudo via CLI.

## Dependências
- DEP-001: Node 20+, npm.

## Estimativa
~0.5 dia
