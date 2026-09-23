# STORY 1.6 — Baseline AWS S3

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento Solana)
**Agente:** @dev (Dex)

## Descrição
Escrever o mesmo payload em S3 (Standard, IA, Glacier Deep Archive) e registrar custo + latência para comparação 1:1 com Solana.

## Critérios de Aceitação
- [ ] Script que faz PUT/GET do mesmo payload em 3 classes S3.
- [ ] Registrar custo por GB/mês de cada classe (Standard US$ 0,023; IA US$ 0,0125; Deep Archive US$ 0,00099).
- [ ] Medir latência de escrita e leitura.
- [ ] Registrar métricas no schema unificado (layer = "aws-s3").

## Notas Técnicas
- Pode usar AWS SDK local com credenciais já existentes (CDK account eworks-dev).
- Deep Archive tem min 180 dias + retrieval lento (não fazer GET real; estimar).

## Dependências
- DEP-002: STORY 1.1 (harness schema).
- DEP-003: credenciais AWS (Cesar).

## Estimativa
~0.5 dia
