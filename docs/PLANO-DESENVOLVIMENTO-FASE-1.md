# Plano de Desenvolvimento — Fase 1 (PoC Armazenamento Solana + Métricas)

**Projeto:** Hackathon Colosseum 2026
**Autor:** @aiox-master (Orion) / @sm (River)
**Data:** 22 Set 2026
**Framework:** AIOX-Core (story-driven, 6 leis)

---

## 1. Objetivo da Fase

Validar empiricamente o custo e a performance de armazenamento na rede Solana (rent, state compression, Irys, Walrus) contra a baseline AWS S3, produzindo uma **matriz de benchmark** com números medidos que alimenta a decisão de placement do produto.

**Critério de done da fase:** `docs/research/BENCHMARK-RESULTS.md` com custo USD/GB + latência + throughput medidos em ≥ 4 camadas + recomendação por caso de uso.

---

## 2. Estrutura de Epics & Stories

### Epic 1 — PoC de Armazenamento Solana (8 stories)

| Story | Título | Dependência | Estimativa | Tipo |
|-------|--------|-------------|------------|------|
| 1.1 | Ambiente Solana + Harness Base | — | 0.5d | Setup |
| 1.2 | Benchmark On-Chain (rent) | 1.1 | 0.5d | Benchmark |
| 1.3 | Benchmark State Compression | 1.1 | 0.5d | Benchmark |
| 1.4 | Benchmark Irys | 1.1 | 0.5d | Benchmark |
| 1.5 | Benchmark Walrus (blob) | 1.1 | 1d | Benchmark |
| 1.6 | Baseline AWS S3 | 1.1, 1.7 | 0.5d | Benchmark |
| 1.7 | Harness de Métricas | 1.1 | 0.5d | Infra |
| 1.8 | Matriz Comparativa (relatório) | 1.2–1.7 | 0.5d | Entrega |

**Total:** ~5 dias (PoC, não produto).

---

## 3. Ordem de Execução (com paralelização)

### Fase A — Fundação (1 dia)
- **1.1** (ambiente) → **1.7** (harness) — sequencial, pois o harness depende do ambiente.
- 1.7 deve sair ANTES dos benchmarks para todos emitirem métricas no mesmo schema.

### Fase B — Benchmarks (2 dias, PARALELO)
- **1.2** (rent) ∥ **1.3** (compression) ∥ **1.4** (Irys) ∥ **1.5** (Walrus) — independentes entre si.
- **1.6** (AWS baseline) pode rodar em paralelo também (não depende de Solana).

### Fase C — Consolidação (1 dia)
- **1.8** (matriz) — depois de todos os benchmarks.

### Diagrama de dependências
```
1.1 → 1.7 → {1.2, 1.3, 1.4, 1.5, 1.6} → 1.8
```

---

## 4. Estratégia de Paralelização (AIOX)

- **Batch 1 (governança):** 1.1 + 1.7 (fundação). NÃO paralelizar — bloqueia o resto.
- **Batch 2 (benchmarks, 4-5 em paralelo):** 1.2, 1.3, 1.4, 1.5, 1.6. Independentes (camadas diferentes, sem estado compartilhado além do harness).
- **Batch 3 (entrega):** 1.8.

**Por quê paralelizar os benchmarks:** cada um toca uma camada distinta, sem FK/shared-state entre eles. Único ponto de contato é o `recordMetric()` do harness (1.7), que é read-only para os benchmarks.

---

## 5. Agentes Responsáveis

| Artefato | Agente |
|----------|--------|
| PRD (epic-1) | @pm |
| Architecture (stack exato) | @architect |
| Stories (1.1–1.8) | @sm |
| Validação de stories | @po |
| Implementação | @dev |
| QA (testes, cobertura) | @qa |
| Push/PR (git) | @devops |

---

## 6. Métricas de Teste & Validação (o que medir)

### Custo (USD/GB)
- rent: lamports/byte efetivo → USD via preço SOL timestampado.
- compression: custo total da árvore + por leaf, × depth/canopy.
- Irys: USD/GB permanente + term.
- Walrus: US$ 0,023/GB/mês (encoded 4,5× — verificar real).
- S3: US$/GB/mês por classe (Standard/IA/Deep Archive).

### Performance
- **Latência escrita** (ms): tempo até confirmação (Solana: ~400ms block time; S3: ms).
- **Latência leitura** (ms): retrieval (S3 Glacier: 12-48h; Irys/Walrus: gateway).
- **Throughput** (MB/s): upload/download.

### Qualidade
- Cobertura de testes ≥ 70% (harness + libs).
- Reprodutibilidade: `npm run bench` regenera tudo.
- Idempotência: re-execução não duplica custo sem registro.

### Thresholds de validação
| Métrica | Alvo | Nota |
|---------|------|------|
| Nº camadas medidas | ≥ 4 | rent, compression, Irys, Walrus, S3 |
| Custo registrado em USD | 100% ops | com preço timestampado |
| Latência medida | 100% ops | escrita + leitura |
| Repro executável | 1 comando | `npm run bench` |

---

## 7. Riscos & Mitigações (da fase)

| Risco | Mitigação |
|-------|-----------|
| SDK Walrus/Irys imaturo | Fallback CLI oficial |
| Custo mainnet alto | Devnet p/ volume; mainnet 1-2 ops teto 0.1 SOL |
| Preço SOL volátil | Registrar no instante + média móvel |
| Rate limit RPC | Backoff exponencial + cache |

---

## 8. Timeline

```
Dia 1 (23 set): 1.1 + 1.7 (fundação)
Dia 2-3 (24-25 set): 1.2–1.6 (benchmarks em paralelo)
Dia 4 (26 set): 1.8 (matriz + relatório) + QA final
Dia 5 (27 set): buffer + revisão @po
```

**Marco de saída:** BENCHMARK-RESULTS.md publicado, decisão de placement atualizada com números reais.

---

## 9. Entregáveis da Fase

1. `docs/prd/epic-1-solana-storage-poc.md` ✅
2. `docs/stories/epic-1/STORY-1.1..1.8-*.md` ✅
3. Código do harness + benchmarks (repo `/root/projects/colosseum-hackathon`)
4. `bench-results.json` + `.csv` (versionados)
5. `docs/research/BENCHMARK-RESULTS.md` (matriz comparativa)
6. `DECISAO-PLACEMENT-SOLANA-VS-AWS.md` atualizado com números reais

---

**Próximo passo:** @architect define stack exato (SDKs + versões) → @po valida stories → @dev implementa Batch 1.
