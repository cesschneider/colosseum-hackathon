# Decisão de Placement: O que vai para Solana vs O que fica na AWS

**Projeto:** Hackathon Colosseum 2026
**Data:** 22 Set 2026
**Objetivo:** Decisão explícita, componente a componente, de onde cada parte do produto deve rodar — Solana (ou redes descentralizadas) versus AWS — com justificativa.

---

## 1. Princípio Norteador

> **Blockchain não é storage nem compute para big data.** Blockchain é **camada de confiança, verificação e monetização**. Dados em volume e processamento pesado ficam na AWS; Solana entra onde o valor é *trustless* (prova, integridade, token-gating, rastreabilidade).

Regra de decisão em 3 perguntas:
1. **O dado é grande (>MB) ou mutável?** → AWS (S3).
2. **O valor está na prova/imutabilidade/permanência?** → Solana/Irys.
3. **É processamento/analytics?** → AWS (Athena/Lambda/EMR).

---

## 2. Tabela de Decisão por Componente

| # | Componente | Camada | Onde | Justificativa |
|---|------------|--------|------|---------------|
| 1 | Série temporal bruta (IPCA, ANP, commodities) | Storage quente | **AWS S3 (Parquet)** | Dados mutáveis, acesso frequente, precisa Athena/query SQL |
| 2 | Histórico arquivado (anos antigos) | Storage frio | **AWS Glacier Deep Archive** | US$ 0,00099/GB/mês — mais barato que qualquer descentralizado |
| 3 | Datasets "âncora" imutáveis (snapshot/versão oficial) | Permanência | **Irys** (US$ 2,33/GB one-time) | Prova de existência + imutabilidade on-chain, custo 100× menor que S3 eterno |
| 4 | Hash/integridade de cada dataset | Provenance | **Solana on-chain** (rent/state compression) | Custo ~zero; verificação trustless por qualquer cliente |
| 5 | Metadados do dataset (fonte, licença, schema, dono) | Provenance | **Solana on-chain** (PDA) | Rastreabilidade + origem auditável |
| 6 | Processamento ETL (normalização, enriquecimento) | Compute | **AWS Lambda/Glue/Batch** | Blockchain não processa; Lambda é barato e escalável |
| 7 | Query analítica (usuário consulta dados) | Compute | **AWS Athena** | US$ 5/TB escaneado; SQL nativo sobre Parquet |
| 8 | API REST (expor dados) | Interface | **AWS API Gateway + Lambda** | US$ 1/1M requests (HTTP); CORS, JWT, escala automática |
| 9 | Dashboard / frontend | Interface | **AWS (S3/CloudFront) ou Vercel/Lovable** | Entrega de UI; não tem papel blockchain |
| 10 | Auth / identidade do usuário | Controle de acesso | **JWT (AWS)** no MVP → **Solana (wallet signature)** no Passo 3 | MVP simples; depois login via wallet = token-gating nativo |
| 11 | Controle de acesso / token-gating a datasets | Monetização | **Solana (programs + SPL/NFT)** | Pagamento por acesso on-chain, sem intermediário |
| 12 | Assinatura de planos (Free/Pro/Enterprise) | Monetização | **Solana (payment)** no Passo 3 | Trilha de pagamento transparente; prêmio pede Solana |
| 13 | Mídia/arquivos de usuários (se houver upload) | Storage | **shdwDrive** (ou S3) | US$ 0,05/GB/ano + UX nativa Solana; S3 se priorizar SLA |
| 14 | Logs / monitoramento / alertas | Ops | **AWS CloudWatch + SNS** | Observabilidade; não há equivalente descentralizado maduro |
| 15 | CI/CD | DevOps | **GitHub Actions + CDK** | Deploy IaC; já definido no Passo 2 |

---

## 3. Mapa Conceitual (Divisão de Responsabilidades)

```
┌─────────────────────────────────────────────────────────┐
│                     AWS (dados & compute)                │
│                                                         │
│  [S3 Parquet] → [Athena] → [Lambda API] → [API Gateway] │
│   dados brutos   query SQL   ETL/transformação   exposição│
│   + Glacier (frio)                                       │
│   + CloudWatch (logs)                                    │
│                                                         │
└───────────────┬─────────────────────────────────────────┘
                │  (hash + metadados + prova)
                ▼
┌─────────────────────────────────────────────────────────┐
│              Solana (confiança & monetização)            │
│                                                         │
│  [On-chain accounts]  hashes + provenance + PDA         │
│  [State compression]  integridade em escala              │
│  [Irys]  datasets âncora permanentes (proof-of-existence)│
│  [shdwDrive]  mídia de usuário (opcional)                │
│  [Programs/SPL]  token-gating + pagamento por acesso     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Fases (Roadmap de Placement)

### Fase 1 — MVP de Dados (atual, sem blockchain)
- **100% AWS**: S3 + Athena + Lambda + API Gateway + dashboard.
- Sem Solana ainda. Entrega valor de dados consolidados.

### Fase 2 — Provenance & Verificação (primeira integração Solana)
- Adiciona **hash on-chain** de cada dataset + metadados (PDA).
- **Irys** para snapshots "âncora" de datasets oficiais.
- Resultado: qualquer cliente pode verificar que o dado que recebeu é o mesmo publicado.

### Fase 3 — Monetização (token-gating)
- **Login via wallet Solana** (substitui JWT).
- **Pagamento por acesso** on-chain (SPL/USDC ou token próprio).
- **shdwDrive** para mídia de usuário, se houver.

---

## 5. Resumo da Decisão (uma frase por domínio)

| Domínio | Decisão |
|---------|---------|
| **Dados brutos / séries** | AWS S3 (+ Glacier frio) |
| **Processamento / ETL / query** | AWS (Lambda + Athena) |
| **Permanência / imutabilidade** | Irys (on-chain proof) |
| **Integridade / provenance** | Solana on-chain (hash) |
| **Controle de acesso / pagamento** | Solana (token-gating) |
| **Mídia de usuário** | shdwDrive (ou S3) |
| **Ops / monitoramento** | AWS CloudWatch |

---

## 6. Fontes

- Docs internos: `ARMAZENAMENTO-DESCENTRALIZADO-SOLANA.md`, `COMPARATIVO-CUSTO-SOLANA-VS-AWS.md`
- Solana docs (rent, state compression, SIMD-0437)
- aws.amazon.com (S3, Athena, Lambda, API Gateway pricing)

---

**Última atualização:** 22 set 2026
