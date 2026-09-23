# Pesquisa: Armazenamento Descentralizado em Larga Escala (Solana & Alternativas)

**Projeto:** Hackathon Colosseum 2026
**Autor:** Pesquisa técnica (B.IA)
**Data:** 22 Set 2026
**Objetivo:** Mapear soluções, tecnologias e frameworks para armazenamento de grandes volumes de dados na rede Solana (análogo ao IPFS da Ethereum), com foco em **custo por GB** e eficiência.

---

## 1. Contexto & Tese

Na Ethereum, o padrão é **IPFS** (roteamento de conteúdo, gratuito) + camada de persistência paga (Filecoin/Arweave/pinning). Na Solana o ecossistema é diferente: o custo de armazenar diretamente on-chain é alto (rent), então surgiram camadas próprias de storage (Shadow Drive), além das redes neutras de chain (Arweave, Irys, Filecoin) que também funcionam com Solana.

**Regra de ouro (repetida em toda a literatura):**
> Mantenha a infra "fria" (Filecoin/Arweave/Irys) e use um gateway "quente" (Shadow Drive/Pinata/Storacha) para acesso.

---

## 2. Soluções Nativas do Ecossistema Solana

### 2.1 ⚠️ shdwDrive / Shadow Drive (GenesysGo) — ABANDONADO

> **Status: projeto descontinuado.** Último release do `shadow-drive` (v1): ago/2023. `shdwDrive-v2-releases` (app Android): fev/2025 (8 stars, 0 issues). Docs oficiais: *"shdwDrive v1.5 is no longer maintained."* **NÃO usar para novos projetos.**

**Substitutos ativos (ver seção 2.4):** Walrus (camada quente), Irys (permanente).

### 2.2 Armazenamento On-Chain Direto (Rent / Contas Solana)

Dados pequenos (hashes, metadados críticos, estado) podem ir on-chain, mas **não** grandes volumes.

| Aspecto | Detalhe |
|---------|---------|
| **Modelo** | "Rent" = depósito **reembolsável** (não é taxa queimada) |
| **Fórmula** | `min_balance = (128 + data_size) × lamports_per_byte` |
| **Limite por conta** | 10 MiB (`MAX_ACCOUNT_DATA_LEN`) |
| **Custo histórico** | 6.960 lamports/byte (depósito) |
| **SIMD-0437 (set 2026)** | Redução de **90%** em 5 etapas → **696 lamports/byte** |
| **Status** | Etapa 1 (9%) live em mainnet; etapa 2 (27%) no testnet; full 90% em Agave 4.4 (nov/2026) |
| **Efeito prático** | Conta de token SPL cai de ~US$ 0,16 → ~US$ 0,016 |

**Conclusão:** rent é **capital imobilizado** (recuperável ao fechar a conta), não custo. Ótimo para estado crítico; inviável para big data (10 MiB/conta, preço por byte muito acima de storage dedicado).

### 2.3 State Compression (Árvores Merkle / Bubblegum cNFT)

Técnica nativa Solana para armazenar **dados de forma comprimida** — hashes em árvore Merkle on-chain, dado completo só no histórico de transações (indexado por RPC/DAS).

| Escala (cNFTs) | Custo total (SOL) | Custo por asset (SOL) |
|-----------------|-------------------|------------------------|
| 10.000 | 0,27 | 0,000027 |
| 100.000 | 0,77 | 0,0000077 |
| 1.000.000 | 5,31 | 0,0000053 |
| 10.000.000 | 50,42 | 0,0000050 |
| 1.000.000.000 | 5.007 | 0,0000050 |

**Uso:** escala massiva de ativos (cNFTs), não para arquivos grandes. Dado bruto fica em transações; só o hash vai na árvore. Útil para indexar/verificar integridade de datasets em escala.

---

## 3. Soluções Cross-Chain (funcionam com Solana)

### 3.1 Arweave — armazenamento permanente (pay-once, store forever)

| Aspecto | Detalhe |
|---------|---------|
| **Modelo** | Pagamento único → fundo de endowment cobre ~200 anos |
| **Custo atual** | **~US$ 36,5 / GB** (ar-fees, set 2026) — flutua com o preço do AR |
| **Custo histórico** | US$ 6–8 / GB (2022-2024); tendência de queda no longo prazo |
| **Per TB** | ~US$ 37.362 (one-time) |
| **Camadas** | Irys (ex-Bundlr) como L2 de pagamento; ArDrive (drive UX) |
| **Nós** | ~8.000 (base menor que IPFS) |

**Quando usar:** NFT metadata/media, registros legais, arquivos históricos, datasets públicos permanentes. Permanência > flexibilidade.

### 3.2 Irys (ex-Bundlr) — "Programmable Datachain" (Layer-1 de dados)

| Aspecto | Detalhe |
|---------|---------|
| **Modelo** | Multi-ledger: term storage (dias/meses/anos) + ledger permanente |
| **Custo permanente** | **~US$ 2,33 / GB** (one-time) — mais barato que Arweave |
| **Custo term** | ~US$ 0,00007358 / GB / epoch (base ~US$ 0,0753/TB/epoch) |
| **Per TB permanente** | ~US$ 2.382 |
| **Uploads < 100 KiB** | Gratuitos |
| **Execução** | IrysVM (EVM-compatible) lê dados on-chain → licensing/royalties/IA |

**Quando usar:** datasets on-chain programáveis, preço mais agressivo que Arweave, integração nativa com Solana (pagamento em SOL via wallet).

### 3.3 Walrus (Mysten Labs / Sui) — camada "quente" ativa (substituto do shdwDrive)

> **Substituto recomendado do shdwDrive.** Projeto muito ativo (mainnet mar/2025, 450 TB, raise US$ 140M de Standard Crypto/a16z/Electric Capital, SDK atualizado ago/2026).

| Aspecto | Detalhe |
|---------|---------|
| **Rede** | Sui (coordenation/governance) + nós de storage próprios |
| **Modelo** | Blob storage com erasure coding (~4,5× encoded + 64 MB/blob) |
| **Custo** | **US$ 0,023 / GB / mês** (fixo, denominado em USD, pago em WAL) |
| **Permanência** | Term storage por epochs (1 epoch = 1 dia testnet / 2 semanas mainnet), extensível |
| **Produtos** | Quilt (batch de arquivos pequenos), Seal (privacidade), MemWal (SDK memória p/ agentes) |
| **Ecosystema** | 450 TB armazenados (superou Arweave), Team Liquid/Decrypt/Allium |

**Quando usar:** dados quentes/mutáveis em volume, storage de blobs, memória de agentes. É cross-chain (não nativo Solana), mas é a alternativa madura e ativamente mantida ao shdwDrive.

**Ressalva:** não é Solana-nativo (roda em Sui). Para integração 100% Solana, usar Irys (paga em SOL).

### 3.4 Filecoin — storage marketplace (rental / cold storage)

| Aspecto | Detalhe |
|---------|---------|
| **Modelo** | Contratos de armazenamento (PoRep/PoSt) com storage providers |
| **Custo cold** | ~US$ 0,002 / GB / mês |
| **Custo hot** | ~US$ 0,02 / GB / mês |
| **Retrieval** | ~US$ 0,01 / GB |
| **Anual/TB** | US$ 200–1.000 (varia por demanda) |
| **Escala** | ~14 exbibytes de dados |

**Quando usar:** grandes datasets mutáveis, AI training data, cold storage. Melhor custo/GB para volume alto de curto-médio prazo.

### 3.4 IPFS — protocolo de roteamento (gratuito, precisa de pinning)

| Aspecto | Detalhe |
|---------|---------|
| **Protocolo** | Gratuito (content-addressing) |
| **Persistência** | NÃO garantida — precisa pinning |
| **Pinning (Pinata)** | ~US$ 0,15–0,50 / GB / mês |
| **Nós** | 1.2M+ |

**Quando usar:** entrega/roteamento de conteúdo; sempre parear com Filecoin/Arweave/Irys para persistência.

---

## 4. Comparativo de Custo por GB (Referência)

| Solução | Modelo | Custo por GB | 1 TB (referência) |
|---------|--------|--------------|-------------------|
| **Solana rent (on-chain)** | Depósito reembolsável | ~696 lamports/byte (pós-redução) | inviável p/ big data |
| **State Compression (cNFT)** | Hash on-chain | ~US$ 0,000005 / asset | escala massiva de ativos |
| **Walrus (blob)** | Recorrente | **US$ 0,023 / GB / mês** (encoded 4,5×) | ~US$ 282 / TB / ano |
| **Irys (permanente)** | One-time | **US$ 2,33 / GB** | ~US$ 2.382 |
| **Arweave (permanente)** | One-time | ~US$ 36,5 / GB | ~US$ 37.362 |
| **Filecoin (cold)** | Recorrente | US$ 0,002–0,02 / GB / mês | US$ 24–240 / ano |
| **IPFS + Pinata** | Recorrente | US$ 0,15–0,50 / GB / mês | US$ 600–1.800 / ano |

**Leitura de custo (ordem de grandeza por TB/ano):**
- Mais barato recorrente: **Filecoin cold (~US$ 24/TB/ano)**; Walrus custa ~US$ 282/TB/ano (encoded 4,5×) — no nível de S3 Standard.
- Mais barato permanente: **Irys (~US$ 2,33/GB)**, depois Arweave (~US$ 36/GB)

---

## 5. Recomendação para o Projeto (Marketplace de Dados BR)

O produto armazena datasets públicos (IPCA, ANP, commodities) com atualização periódica — **dados mutáveis, em volume crescente, com acesso frequente**. Isso muda a escolha:

**Arquitetura híbrida recomendada (fase MVP → Passo 3 Solana):**

1. **Dados brutos / série temporal** → AWS S3 (Athena/Parquet) como já definido no Passo 2. Custo: US$ 0,023/GB/mês, sem taxa de egresso complexa, SQL nativo. **Não migrar para blockchain ainda.**

2. **Hashes + prova de integridade / provenance** → **Solana on-chain (rent)** ou **state compression**. Armazena só o fingerprint (CID/hash) de cada dataset, não o dado. Custo desprezível; dá verificação de integridade e rastreabilidade on-chain.

3. **Datasets públicos "âncora" / permanentes** → **Irys** (US$ 2,33/GB one-time) como backup imutável e proof-of-existence, com wallet Solana.

4. **Arquivos/mídia de usuários** (Passo 3, se houver) → **S3** (custo, 4,5× mais barato) ou **Walrus** (quando o valor é verificabilidade/descentralização, ex. prova de autenticidade).

**Racional:** big data não vai pra blockchain (custoso e lento); blockchain entra como **camada de verificação e monetização** (provenance, acesso token-gated, prova de que o dataset é autêntico), não como storage principal.

---

## 6. Fontes

- youngju.dev — "Decentralized Storage 2026 Complete Guide" (Filecoin, Arweave, Walrus, Shadow Drive, Irys, EigenDA)
- ar-fees.arweave.net — calculadora oficial de custo Arweave
- docs.shdwdrive.com — FAQ de preços (US$ 0,05/GiB/ano)
- Solana docs — Account Structure / Reduced Rent (SIMD-0437)
- Metaplex docs — Bubblegum (state compression) e custos de Merkle tree
- Irys Whitepaper — pricing de storage permanente (US$ 2,33/GB)
- msblabs.org / dlt.sg / steyble.com — comparativos IPFS vs Arweave vs Filecoin

---

**Última atualização:** 22 set 2026
