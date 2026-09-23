# Diagrama de Arquitetura C4 — Marketplace de Dados Públicos Micro (BR)

**Projeto:** Hackathon Colosseum 2026
**Data:** 22 Set 2026
**Modelo:** C4 (Context → Container → Component → Code)
**Base:** Solução inicialmente proposta pelo Marcelo + decisão de placement (AWS + Solana)

---

## C4 — Nível 1: Contexto (System Context)

Quem são os usuários e como interagem com o sistema.

```mermaid
flowchart TB
    subgraph Users["Pessoas / Atores"]
        Consultor["Consultor / Analista<br/>(Marcelo)"]
        Empresa["PME / Empresa<br/>(cliente final)"]
        Admin["Admin do Time<br/>(Cesar)"]
    end

    Platform["Marketplace de Dados<br/>Públicos Micro (BR)<br/>[Sistema]"]
    Solana["Rede Solana<br/>[Sistema Externo]"]

    Consultor -->|"consulta dados micro (API/dashboard)"| Platform
    Empresa -->|"assina plano / consome dados"| Platform
    Admin -->|"gerencia datasets & ingestão"| Platform

    Platform -->|"prova de integridade + token-gating"| Solana
```

---

## C4 — Nível 2: Contêineres (Containers)

```mermaid
flowchart TB
    subgraph AWS["AWS (Dados & Compute)"]
        S3["S3 Data Lake<br/>(Parquet particionado)"]
        Glacier["S3 Glacier<br/>(arquivo frio)"]
        Athena["Athena<br/>(query SQL)"]
        Ingest["Lambda Ingestão<br/>(ETL)"]
        API["Lambda API +<br/>API Gateway"]
        Frontend["Dashboard<br/>(Next.js/Recharts)"]
    end

    subgraph Web3["Solana (nativo)"]
        Chain["Solana Programs<br/>(storage + provenance)"]
        Compress["State Compression<br/>(Merkle integridade)"]
    end

    Ingest -->|"escreve Parquet"| S3
    S3 -->|"lifecycle"| Glacier
    S3 -->|"scaneia"| Athena
    API -->|"query"| Athena
    Frontend -->|"REST"| API

    Ingest -->|"publica hash/proof"| Chain
    Chain -->|"integridade em escala"| Compress
```

---

## C4 — Nível 3: Componentes (dentro da Lambda de Ingestão + API)

```mermaid
flowchart LR
    subgraph IngestLambda["Lambda Ingestão (por dataset)"]
        Fetch["Fetcher<br/>(IBGE/ANP/WorldBank)"]
        Parse["Parser<br/>(normalização)"]
        Validate["Validator<br/>(schema + quality)"]
        Write["Parquet Writer"]
        Hash["Hash & Sign<br/>(provenance)"]
    end

    Fetch --> Parse --> Validate --> Write
    Write --> S3["S3 Parquet"]
    Validate --> Hash --> Chain["Solana on-chain"]

    subgraph ApiLambda["Lambda API"]
        Auth["JWT / Wallet Auth"]
        Router["Router (datasetId, range)"]
        Query["Athena Query Builder"]
        Formatter["Response Formatter"]
    end

    Auth --> Router --> Query --> Formatter
    Query --> Athena["Athena"]
```

---

## C4 — Nível 4: Código (exemplo — fluxo de ingestão IPCA)

```mermaid
sequenceDiagram
    participant EB as EventBridge (cron)
    participant L as Lambda Ingest
    participant IBGE as IBGE API
    participant S3 as S3 Parquet
    participant Sol as Solana (programa)

    EB->>L: trigger (mensal/dia 15)
    L->>IBGE: GET agregado IPCA
    IBGE-->>L: JSON série temporal
    L->>L: parse + normalize + validate
    L->>S3: PUT parquet (particionado year/month)
    L->>L: calcula hash (SHA-256) do arquivo
    L->>Sol: registra hash + metadados (programa PDA)
    L-->>EB: 200 (recordsCount)
```

---

## Notas de Decisão (ligadas ao placement)

- **Dados brutos & query** ficam na AWS (S3 + Athena) — ver `DECISAO-PLACEMENT-SOLANA-VS-AWS.md`.
- **Solana nativo** entra como camada de *provenance* (hash on-chain via programa próprio) e *monetização* (token-gating), não como storage de big data.
- **Sem storage cross-chain** (Irys/Walrus/Arweave) — fora de escopo por CON-000.
- **State compression** (Merkle) para integridade em escala, quando o nº de assets é grande.

---

**Última atualização:** 22 set 2026
