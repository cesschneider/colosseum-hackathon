# Decisão de Placement: O que vai para Solana NATIVO vs O que fica na AWS

**Projeto:** Hackathon Colosseum 2026
**Data:** 22 Set 2026 (revisado)
**Objetivo:** Decisão explícita, componente a componente, de onde cada parte do produto deve rodar — **Solana nativo** versus AWS — com justificativa.
**Constraint HARD:** somente tecnologias nativas Solana (sem cross-chain: Walrus/Sui, Irys-L1, Arweave, Filecoin, IPFS estão FORA).

---

## 1. Princípio Norteador

> **Blockchain não é storage nem compute para big data.** Blockchain é **camada de confiança, verificação e monetização**. Dados em volume e processamento pesado ficam na AWS; Solana nativo entra onde o valor é *trustless* (prova, integridade, token-gating, rastreabilidade).

Regra de decisão em 3 perguntas:
1. **O dado é grande (>MB) ou mutável?** → AWS (S3).
2. **O valor está na prova/imutabilidade/integridade?** → Solana nativo (rent/compression/programa).
3. **É processamento/analytics?** → AWS (Athena/Lambda/EMR).

**Nota (22 set):** não existe storage "quente"/mutável nativo Solana ativo (shdwDrive abandonado; Irys virou L1 própria). Portanto, todo storage de volume é AWS; Solana nativo cobre **exclusivamente** provenance/integridade/token-gating.

---

## 2. Tabela de Decisão por Componente

| # | Componente | Camada | Onde | Justificativa |
|---|------------|--------|------|---------------|
| 1 | Série temporal bruta (IPCA, ANP, commodities) | Storage quente | **AWS S3 (Parquet)** | Dados mutáveis, acesso frequente, precisa Athena/query SQL |
| 2 | Histórico arquivado (anos antigos) | Storage frio | **AWS Glacier Deep Archive** | US$ 0,00099/GB/mês — mais barato que qualquer descentralizado |
| 3 | Datasets "âncora" imutáveis (snapshot/versão oficial) | Permanência | **AWS S3 + hash on-chain** | Sem storage permanente nativo Solana; imutabilidade via hash no programa próprio |
| 4 | Hash/integridade de cada dataset | Provenance | **Solana nativo** (programa próprio + rent) | Custo ~zero; verificação trustless on-chain |
| 5 | Metadados do dataset (fonte, licença, schema, dono) | Provenance | **Solana nativo** (PDA no programa) | Rastreabilidade + origem auditável |
| 6 | Processamento ETL (normalização, enriquecimento) | Compute | **AWS Lambda/Glue/Batch** | Blockchain não processa; Lambda é barato e escalável |
| 7 | Query analítica (usuário consulta dados) | Compute | **AWS Athena** | US$ 5/TB escaneado; SQL nativo sobre Parquet |
| 8 | API REST (expor dados) | Interface | **AWS API Gateway + Lambda** | US$ 1/1M requests (HTTP); CORS, JWT, escala automática |
| 9 | Dashboard / frontend | Interface | **AWS (S3/CloudFront) ou Vercel/Lovable** | Entrega de UI; não tem papel blockchain |
| 10 | Auth / identidade do usuário | Controle de acesso | **JWT (AWS)** no MVP → **Solana (wallet signature)** no Passo 3 | MVP simples; depois login via wallet = token-gating nativo |
| 11 | Controle de acesso / token-gating a datasets | Monetização | **Solana (programs + SPL/NFT)** | Pagamento por acesso on-chain, sem intermediário |
| 12 | Assinatura de planos (Free/Pro/Enterprise) | Monetização | **Solana (payment)** no Passo 3 | Trilha de pagamento transparente; prêmio pede Solana |
| 13 | Mídia/arquivos de usuários (se houver upload) | Storage | **AWS S3** | Sem storage quente nativo Solana; S3 é a única opção viável |
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
│  [Programa próprio]   storage + verify de dataset        │
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
- Adiciona **hash on-chain** de cada dataset + metadados (PDA no programa próprio).
- Resultado: qualquer cliente pode verificar que o dado que recebeu é o mesmo publicado.

### Fase 3 — Monetização (token-gating)
- **Login via wallet Solana** (substitui JWT).
- **Pagamento por acesso** on-chain (SPL/USDC ou token próprio).

---

## 5. Resumo da Decisão (uma frase por domínio)

| Domínio | Decisão |
|---------|---------|
| **Dados brutos / séries** | AWS S3 (+ Glacier frio) |
| **Processamento / ETL / query** | AWS (Lambda + Athena) |
| **Permanência / imutabilidade** | AWS S3 + hash on-chain (programa) |
| **Integridade / provenance** | Solana nativo (programa + rent/compression) |
| **Controle de acesso / pagamento** | Solana (token-gating) |
| **Mídia de usuário** | AWS S3 (sem storage quente nativo Solana) |
| **Ops / monitoramento** | AWS CloudWatch |

---

## 6. Fontes

- Docs internos: `ARMAZENAMENTO-DESCENTRALIZADO-SOLANA.md`, `COMPARATIVO-CUSTO-SOLANA-VS-AWS.md`
- Solana docs (rent, state compression, SIMD-0437)
- aws.amazon.com (S3, Athena, Lambda, API Gateway pricing)

---

**Última atualização:** 22 set 2026
