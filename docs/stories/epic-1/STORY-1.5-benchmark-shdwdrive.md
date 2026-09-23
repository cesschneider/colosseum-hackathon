# STORY 1.5 — Benchmark shdwDrive

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento Solana)
**Agente:** @dev (Dex)

## Descrição
Criar storage account e bucket no shdwDrive, fazer upload/download de dados mutáveis, e medir custo + latência + throughput.

## Critérios de Aceitação
- [ ] Criar storage account (free 5GB) no shdwDrive.
- [ ] Upload de payload (1MB, 10MB, 100MB) e registrar custo (US$ 0,05/GiB/ano).
- [ ] Download/leitura: medir latência (ms) e throughput (MB/s).
- [ ] Registrar métricas no schema unificado.

## Notas Técnicas
- SDK `@shadow-drive/sdk`; fallback CLI `shadow-drive` se SDK imaturo.
- Custo mutable ref: US$ 0,05/GiB/ano (~US$ 0,000274/GiB/epoch).

## Dependências
- DEP-002: STORY 1.1.

## Estimativa
~1 dia (SDK pode ter curva)
