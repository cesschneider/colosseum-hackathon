# Plano de Desenvolvimento — Fase 1 (PoC Armazenamento NATIVO Solana + Métricas)

**Projeto:** Hackathon Colosseum 2026
**Autor:** @aiox-master (Orion) / @sm (River)
**Data:** 22 Set 2026
**Framework:** AIOX-Core (story-driven, 6 leis)

---

## 1. Objetivo da Fase

Validar empiricamente o custo e a performance de armazenamento **nativo Solana** (rent, state compression, programa próprio) contra a baseline AWS S3, produzindo uma **matriz de benchmark** com números medidos que alimenta a decisão de placement.

**Constraint HARD (CON-000):** somente tecnologias nativas Solana. Nenhuma cross-chain (Walrus/Sui, Irys-L1, Arweave, Filecoin, IPFS).

**Critério de done:** `docs/research/BENCHMARK-RESULTS.md` com custo + latência + throughput medidos nas 3 camadas nativas + recomendação por caso de uso.

---

## 2. Estrutura de Epics & Stories

### Epic 1 — PoC de Armazenamento NATIVO Solana (7 stories)

| Story | Título | Dependência | Estimativa | Tipo |
|-------|--------|-------------|------------|------|
| 1.1 | Ambiente Solana + Harness Base | — | 0.5d | Setup |
| 1.2 | Benchmark On-Chain (rent) | 1.1 | 0.5d | Benchmark |
| 1.3 | Benchmark State Compression | 1.1 | 0.5d | Benchmark |
| 1.4 | Programa Próprio Storage + Provenance | 1.1 | 1d | Benchmark |
| 1.5 | Baseline AWS S3 | 1.1, 1.6 | 0.5d | Benchmark |
| 1.6 | Harness de Métricas | 1.1 | 0.5d | Infra |
| 1.7 | Matriz Comparativa (relatório) | 1.2–1.6 | 0.5d | Entrega |

**Total:** ~4 dias (PoC, não produto).

---

## 3. Ordem de Execução (com paralelização)

### Fase A — Fundação (1 dia)
- **1.1** (ambiente) → **1.6** (harness) — sequencial, pois o harness depende do ambiente.
- 1.6 deve sair ANTES dos benchmarks para todos emitirem métricas no mesmo schema.

### Fase B — Benchmarks (2 dias, PARALELO)
- **1.2** (rent) ∥ **1.3** (compression) ∥ **1.4** (programa próprio) — independentes entre si.
- **1.5** (AWS baseline) pode rodar em paralelo também (não depende de Solana).

### Fase C — Consolidação (1 dia)
- **1.7** (matriz) — depois de todos os benchmarks.

### Diagrama de dependências
```
1.1 → 1.6 → {1.2, 1.3, 1.4, 1.5} → 1.7
```

---

## 4. Estratégia de Paralelização (AIOX)

- **Batch 1 (governança):** 1.1 + 1.6 (fundação). NÃO paralelizar — bloqueia o resto.
- **Batch 2 (benchmarks, 4 em paralelo):** 1.2, 1.3, 1.4, 1.5. Independentes (camadas diferentes; único ponto de contato é o `recordMetric()` read-only).
- **Batch 3 (entrega):** 1.7.

---

## 5. Agentes Responsáveis

| Artefato | Agente |
|----------|--------|
| PRD (epic-1) | @pm |
| Architecture (programa Rust exato) | @architect |
| Stories (1.1–1.7) | @sm |
| Validação de stories | @po |
| Implementação | @dev |
| QA (testes, cobertura) | @qa |
| Push/PR (git) | @devops |

---

## 6. Métricas de Teste & Validação

### Custo (USD)
- rent: lamports/byte efetivo → USD via preço SOL timestampado.
- compression: custo total da árvore + por leaf, × depth/canopy.
- programa próprio: custo de deploy + custo por operação (store/verify/update).
- S3: US$/GB/mês por classe.

### Performance
- **Latência escrita** (ms): tempo até confirmação (Solana ~400ms block time; S3 ms).
- **Latência leitura** (ms).
- **Throughput** (MB/s): upload/download.

### Qualidade
- Cobertura ≥ 70% (harness + libs).
- Reprodutibilidade: `npm run bench`.
- Idempotência.

### Thresholds
| Métrica | Alvo |
|---------|------|
| Nº camadas medidas | 3 nativas Solana + S3 |
| Custo em USD | 100% ops (preço timestampado) |
| Latência medida | 100% ops |
| Repro executável | 1 comando |

---

## 7. Riscos & Mitigações

| Risco | Mitigação |
|-------|-----------|
| Programa Rust/Anchor tem curva | Exemplo mínimo; Cesar domina Rust |
| Custo mainnet alto | Devnet p/ volume; mainnet teto 0.1 SOL |
| Preço SOL volátil | Registrar no instante + média móvel |
| Rate limit RPC | Backoff exponencial + cache |
| Limite 10 MiB/conta | Fracionar payload; documentar |

---

## 8. Timeline

```
Dia 1 (23 set): 1.1 + 1.6 (fundação)
Dia 2-3 (24-25 set): 1.2–1.5 (benchmarks em paralelo)
Dia 4 (26 set): 1.7 (matriz + relatório) + QA final
```

**Marco de saída:** BENCHMARK-RESULTS.md publicado; decisão de placement atualizada com números reais.

---

## 9. Entregáveis da Fase

1. `docs/prd/epic-1-solana-storage-poc.md` ✅
2. `docs/stories/epic-1/STORY-1.1..1.7-*.md` ✅
3. Código do harness + benchmarks + programa Anchor
4. `bench-results.json` + `.csv` (versionados)
5. `docs/research/BENCHMARK-RESULTS.md` (matriz)
6. `DECISAO-PLACEMENT-SOLANA-VS-AWS.md` atualizado

---

**Próximo passo:** @architect define o programa Rust/Anchor exato → @po valida → @dev implementa Batch 1.
