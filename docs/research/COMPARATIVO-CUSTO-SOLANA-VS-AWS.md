# Comparativo de Custo: Solana/Descentralizado vs AWS — por Caso de Uso

**Projeto:** Hackathon Colosseum 2026
**Data:** 22 Set 2026
**Objetivo:** Comparar, para cada caso de uso do produto, o custo de armazenamento/processamento em Solana (e redes descentralizadas) versus AWS. Base para decidir o que vai para onde.

---

## 1. Tabela-Mestra de Preços (referência set/2026)

### Armazenamento Descentralizado (da pesquisa anterior)

| Solução | Modelo | Custo |
|---------|--------|-------|
| shdwDrive (mutable) | Recorrente | US$ 0,05 / GB / ano |
| Irys (permanente) | One-time | US$ 2,33 / GB |
| Arweave (permanente) | One-time | ~US$ 36,5 / GB |
| Filecoin cold | Recorrente | US$ 0,002–0,02 / GB / mês |
| Filecoin hot | Recorrente | US$ 0,02 / GB / mês |
| IPFS + Pinata | Recorrente | US$ 0,15–0,50 / GB / mês |
| Solana rent (on-chain) | Depósito reembolsável | ~696 lamports/byte (pós SIMD-0437) |

### AWS (US East, 2026)

| Serviço | Classe/Nível | Custo |
|---------|--------------|-------|
| **S3 Standard** | Acesso frequente | US$ 0,023 / GB / mês |
| **S3 Standard-IA** | Acesso mensal | US$ 0,0125 / GB / mês (+ retrieval US$ 0,01/GB) |
| **S3 One Zone-IA** | Acesso mensal, 1 AZ | US$ 0,010 / GB / mês |
| **S3 Glacier Instant** | Acesso trimestral | US$ 0,004 / GB / mês |
| **S3 Glacier Flexible** | Acesso anual | US$ 0,0036 / GB / mês |
| **S3 Glacier Deep Archive** | Acesso raro | US$ 0,00099 / GB / mês |
| **S3 Data Transfer Out** | Egresso | US$ 0,09 / GB (100 GB free/mês) |
| **Athena** | Query sob demanda | US$ 5 / TB escaneado |
| **Lambda** | Compute | US$ 0,20 / 1M requests + US$ 0,0000166667 / GB-seg |
| **API Gateway HTTP** | Requests | US$ 1,00 / 1M |
| **API Gateway REST** | Requests | US$ 3,50 / 1M |
| **CloudWatch Logs** | Ingestão | US$ 0,50 / GB |

---

## 2. Comparativo por Caso de Uso

### Caso A — Série temporal pública (IPCA, ANP, commodities): ~GBs a TBs, acesso frequente

| | AWS | Descentralizado | Vencedor |
|---|---|---|---|
| **Custo 1 TB / ano (acesso quente)** | S3 Standard: US$ 0,023 × 12 × 1024 = **US$ 282/ano** | shdwDrive: **US$ 51/ano** | 🏆 Descentralizado (5× mais barato) |
| **Custo 1 TB / ano (arquivo frio)** | Deep Archive: US$ 0,00099 × 12 × 1024 = **US$ 12/ano** | Filecoin cold: US$ 0,002 × 12 × 1024 = **US$ 25/ano** | 🏆 AWS (2× mais barato) |
| **Query SQL ad-hoc** | Athena US$ 5/TB escaneado | Não existe nativamente | 🏆 AWS |
| **Latência de leitura** | ms (S3 Standard) | gateway-dependente | 🏆 AWS (garantia de SLA) |
| **Egresso** | US$ 0,09/GB | variável | ⚖️ Depende |

**Conclusão:** para dados quentes com query SQL, AWS ganha por funcionalidade (Athena/Parquet). shdwDrive é mais barato no armazenamento bruto, mas perde em query + latência garantida.

### Caso B — Datasets "âncora" permanentes (imutáveis, proof-of-existence)

| | AWS | Descentralizado | Vencedor |
|---|---|---|---|
| **Custo por GB, uma vez, para sempre** | S3 exige pagamento eterno (US$ 0,023/GB/mês → US$ 276/GB após 100 anos) | Irys **US$ 2,33/GB** one-time; Arweave US$ 36/GB | 🏆 Descentralizado (Irys) |
| **Prova de imutabilidade on-chain** | Não (S3 Object Lock é centralizado) | Nativo (content hash on-chain) | 🏆 Descentralizado |
| **Confiabilidade** | 11 noves durabilidade | ~8.000 nós (Arweave) | ⚖️ Empate conceitual |

**Conclusão:** permanência + prova de imutabilidade → **Irys** é imbatível (US$ 2,33/GB vs US$ 36/GB Arweave).

### Caso C — Provenance / integridade de dataset (hash + assinatura)

| | AWS | Descentralizado | Vencedor |
|---|---|---|---|
| **Custo de um hash (32 bytes)** | ~US$ 0 (S3 metadata) | Solana rent: desprezível (~US$ 0,0001); state compression: ~US$ 0,000005/asset | ⚖️ Empate (ambos ~zero) |
| **Verificação trustless** | ❌ Centralizado (AWS é o árbitro) | ✅ On-chain, verificável por qualquer um | 🏆 Descentralizado |
| **Integração com token-gating** | ❌ Não | ✅ Nativo (programs Solana) | 🏆 Descentralizado |

**Conclusão:** provenance/verificação → **Solana on-chain**. Custo é irrelevante; o valor é trustless.

### Caso D — Mídia/arquivos de usuários (upload, mutável, acesso frequente)

| | AWS | Descentralizado | Vencedor |
|---|---|---|---|
| **Custo 1 TB / ano (mutável)** | S3 Standard US$ 282/ano + egresso | shdwDrive US$ 51/ano | 🏆 Descentralizado (5×) |
| **UX de integração Solana** | Não (precisa ponte) | ✅ Nativo (wallet Phantom) | 🏆 Descentralizado |
| **SLA / suporte** | ✅ Garantido | ⚠️ Menor adoção | 🏆 AWS |

**Conclusão:** mídia de usuário em app Solana-native → **shdwDrive** (custo + UX). Se a prioridade for SLA → S3.

### Caso E — Processamento / query / analytics (o "big data" do Marcelo)

| | AWS | Descentralizado | Vencedor |
|---|---|---|---|
| **SQL analítico** | Athena (US$ 5/TB), Redshift, EMR/Spark | ❌ Não existe nativamente | 🏆 AWS |
| **ETL/transformação** | Lambda/Glue/Batch | ❌ Não | 🏆 AWS |
| **Compute over data** | ✅ Bacalhau/EC2 | Filecoin FVM (experimental) | 🏆 AWS |

**Conclusão:** processamento/analytics → **100% AWS**. Blockchain não processa big data.

---

## 3. Resumo Executivo de Custo (por TB, cenário representativo)

| Cenário | AWS | Descentralizado | Economia |
|---------|-----|-----------------|----------|
| 1 TB dados quentes / ano | US$ 282 | US$ 51 (shdwDrive) | 5× mais barato no descentralizado |
| 1 TB arquivo frio / ano | US$ 12 | US$ 25 (Filecoin) | 2× mais barato no AWS |
| 1 GB permanente / para sempre | US$ 276 (100 anos) | US$ 2,33 (Irys) | 100× mais barato no descentralizado |
| Query 1 TB escaneado | US$ 5 (Athena) | n/a | AWS único |

**Leitura:** AWS é imbatível em **frio + query/processamento**; o descentralizado é imbatível em **permanência + custo de armazenamento quente + prova trustless**.

---

## 4. Fontes

- aws.amazon.com/s3/pricing — storage classes (US East, 2026)
- aws.amazon.com/athena/pricing — US$ 5/TB escaneado
- aws.amazon.com/api-gateway/pricing + apigatewaycost.com — HTTP vs REST
- leanopstech.com — Lambda pricing + custos "escondidos"
- docs.shdwdrive.com — US$ 0,05/GiB/ano
- Irys Whitepaper — US$ 2,33/GB permanente
- ar-fees.arweave.net — US$ 36,5/GB Arweave

---

**Última atualização:** 22 set 2026
