# STORY 1.5 — Benchmark Walrus (Blob Storage)

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento Solana)
**Agente:** @dev (Dex)

## Descrição
Configurar client Walrus (substituto do shdwDrive, que está abandonado), fazer upload/download de blobs, e medir custo real (encoded size 4,5×) + latência + throughput + verificabilidade.

## Critérios de Aceitação
- [ ] Instalar CLI `walrus` + `suiup` (testnet) e configurar wallet Sui.
- [ ] Obter SUI (gas) + WAL (storage) de faucet/swap testnet.
- [ ] Upload de blob (1MB, 10MB, 100MB) via CLI/SDK.
- [ ] Registrar custo real: `walrus info` + encoded size (4,5× original + 64MB/blob) → US$ 0,023/GB/mês.
- [ ] Download/leitura: medir latência (ms) e throughput (MB/s).
- [ ] Registrar métricas no schema unificado (`layer = "walrus"`).

## Notas Técnicas
- Custo efetivo: `encoded_GB = 4,5 × original_GB + 0,064`; `custo_mês = encoded_GB × US$ 0,023`.
- Walrus é Sui (não Solana nativo) — anotar isso no resultado.
- `walrus store --dry-run` confirma encoded size antes de gastar.

## Dependências
- DEP-002: STORY 1.1 (harness schema).

## Estimativa
~1 dia (curva do CLI Sui/Walrus)
