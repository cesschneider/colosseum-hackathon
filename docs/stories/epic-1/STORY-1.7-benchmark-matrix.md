# STORY 1.7 — Matriz de Benchmark Comparativa (Relatório Final)

**Status:** Draft
**Epic:** 1 (PoC de Armazenamento NATIVO Solana)
**Agente:** @pm (Morgan) / @po (Pax)

## Descrição
Consolidar os resultados medidos em uma **matriz comparativa Solana-nativo × AWS** com recomendação por caso de uso.

## Critérios de Aceitação
- [ ] Matriz: linhas = camadas (rent, compression, program, S3×3); colunas = custo USD/byte ou /GB, latência escrita, latência leitura, throughput, permanência.
- [ ] Recomendação explícita por caso de uso (dados quentes, frios, provenance, integridade).
- [ ] Publicar como `docs/research/BENCHMARK-RESULTS.md` + tabela CSV.
- [ ] Atualizar `DECISAO-PLACEMENT-SOLANA-VS-AWS.md` com números reais.
- [ ] Linkar relatório no README.

## Notas Técnicas
- Números reais (medidos), não estimativas. Citar timestamp + preço SOL usado.
- Reforçar a tese: Solana nativo = provenance/integridade; AWS = storage de volume.

## Dependências
- DEP-004: STORY 1.2–1.6.

## Estimativa
~0.5 dia
