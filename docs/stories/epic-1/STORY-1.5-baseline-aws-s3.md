# STORY 1.5 — Baseline AWS S3

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento NATIVO Solana)
**Agente:** @dev (Dex)

## Descrição
Escrever o mesmo payload em S3 (Standard, IA, Glacier Deep Archive) e registrar custo + latência para comparação 1:1 com as camadas nativas Solana.

## Critérios de Aceitação
- [ ] Script que faz PUT/GET do mesmo payload em 3 classes S3.
- [ ] Registrar custo por GB/mês (Standard US$ 0,023; IA US$ 0,0125; Deep Archive US$ 0,00099).
- [ ] Medir latência de escrita e leitura.
- [ ] Registrar métricas no schema unificado (`layer = "aws-s3"`).

## Notas Técnicas
- AWS SDK local com credenciais existentes (CDK account eworks-dev).
- Deep Archive: min 180 dias + retrieval lento (estimar, não fazer GET real).

## Dependências
- DEP-002: STORY 1.1 (schema).
- DEP-003: credenciais AWS (Cesar).

## Estimativa
~0.5 dia
