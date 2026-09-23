# STORY 1.8 — Matriz de Benchmark Comparativa (Relatório Final)

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento Solana)
**Agente:** @pm (Morgan) / @po (Pax)

## Descrição
Consolidar os resultados medidos em uma **matriz comparativa Solana × AWS** com recomendação por caso de uso.

## Critérios de Aceitação
- [ ] Matriz: linhas = camadas (rent, compression, Irys, Walrus, S3×3); colunas = custo USD/GB, latência escrita, latência leitura, throughput, permanência.
- [ ] Recomendação explícita por caso de uso (dados quentes, frios, âncora, provenance, mídia).
- [ ] Publicar como `docs/research/BENCHMARK-RESULTS.md` + tabela CSV.
- [ ] Atualizar `DECISAO-PLACEMENT-SOLANA-VS-AWS.md` com números reais (substituir estimativas).
- [ ] Linkar relatório no README.

## Notas Técnicas
- Números reais (medidos), não estimativas. Citar timestamp + preço SOL usado.

## Dependências
- DEP-004: STORY 1.2–1.7 (todos os benchmarks).

## Estimativa
~0.5 dia
