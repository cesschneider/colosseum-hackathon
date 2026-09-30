# Plano ETL — Extração em `/data`, Upload S3, Metadata/Schema

**Projeto:** colosseum-hackathon · **Autor:** B.IA (Hermes) · **Data:** 2026-09-30
**Status:** Plano aprovado para implementação · **Branch:** `feat/dados-municipais`

---

## 1. Objetivo

Transformar a coleta ad-hoc de dados municipais em uma **pipeline ETL reutilizável**:

```
EXTRACT (R, /data)  →  UPLOAD raw S3  →  TRANSFORM (R, /data)  →  UPLOAD curated S3
                      →  METADATA/SCHEMA S3  →  MANIFEST  →  CLEANUP /data
```

A fase de extração é **genérica**: qualquer fonte nova entra no pipeline sem código
novo de orquestração — basta ter os scripts `01_extracao_<fonte>.R` e
`02_tratamento_<fonte>.R` no padrão do repositório (`fontes/<fonte>/`).

**Regra de ouro:** `/data` é *staging temporário*. Nada permanece nele após o
upload verificado para o S3. O S3 é a fonte da verdade (versionado + SSE-S3).

---

## 2. Restrições de disco (motivo do desenho)

| Volume | Total | Usado | Livre |
|---|---|---|---|
| `/` (sistema) | 116 GB | cronicamente cheio | ~13 GB |
| `/data` (staging ETL) | 220 GB | 188 GB (docker, k3s, langfuse...) | **~20 GB** |

Os brutos completos das 20 fontes somam **~55-65 GB** — **não cabem de uma vez**.
Por isso o pipeline opera **um fonte por vez**, com pico de disco limitado ao
tamanho da fonte em processamento. Fontes pesadas (RAIS ~40 GB) são fatiadas
por ano (ver §7).

---

## 3. Arquitetura

```
                    ┌──────────────────────────────────────────────┐
                    │  /data/colosseum/staging   (volume temporário)│
                    │                                              │
 fontes/<fonte>/    │  brutos/<fonte>/          tratados/<fonte>/  │
 01_extracao.R ────►│  (originais preservados)  (CSV municipal)     │
 02_tratamento.R ──►│         │                        │           │
                    └─────────┼────────────────────────┼──────────┘
                              │ aws s3 sync            │ aws s3 sync
                              ▼                        ▼
        s3://colosseum-dados-municipais-dev/
        ├── raw/<fonte>/...              (brutos, STANDARD_IA, imutável)
        ├── curated/<fonte>/...          (tratados, STANDARD)
        ├── metadata/<fonte>.schema.json (schema+integridade)
        ├── catalog/dicionario_municipios.csv
        └── manifest/manifest-AAAAMMDD.csv  (SHA-256, append)
```

**Por que esse layout:**
- `raw/` preserva o original da fonte (reprocessável sem re-download; auditável).
- `curated/` é o que Athena/Glue consulta (prefix já registrado no Glue DB).
- `metadata/` permite reconstruir tabelas Glue e o catálogo da API sem ler os
  CSVs (processamento posterior automatizado).
- `manifest/` é a base da provenança (fase 5: hash on-chain Solana).

---

## 4. Extração reutilizável (contrato da fonte)

A biblioteca comum do pipeline R já suporta redirecionar todos os dados para um
diretório arbitrário via variável de ambiente — **sem alterar código das fontes**:

```r
# config.R (existente):
DIR_DADOS <- Sys.getenv("PAINEL_DADOS", unset = file.path(DIR_RAIZ, "dados"))
```

Portanto a extração genérica é:

```bash
export PAINEL_DADOS=/data/colosseum/staging
export PAINEL_ANO_INICIAL=2020        # opcional: recorte para testes
Rscript fontes/<fonte>/01_extracao_<fonte>.R   # → $PAINEL_DADOS/brutos/<fonte>/
Rscript fontes/<fonte>/02_tratamento_<fonte>.R # → $PAINEL_DADOS/tratados/<fonte>/
```

**Contrato de uma fonte** (já satisfeito por todas as 20 do Marcelo):
1. Pasta `fontes/<fonte>/` com `01_extracao_<fonte>.R` + `02_tratamento_<fonte>.R`.
2. Brutos preservados como baixados; tratados em `<fonte>_municipal.csv`
   (+ `<fonte>_dicionario_variaveis.csv`), UTF-8, separador `,`, decimal `.`.
3. Idempotente/reutilizável: re-execução pula arquivos já baixados (compara
   tamanho), permitindo retomada de lote interrompido.

**Orquestrador único:** `scripts/etl-fonte.sh <fonte>` executa o ciclo completo
(abaixo) para qualquer fonte. Nenhum orquestrador por fonte.

---

## 5. Ciclo ETL por fonte (`scripts/etl-fonte.sh`)

```
1. EXTRACT      PAINEL_DADOS=/data/colosseum/staging → Rscript 01_extracao_<fonte>.R
2. UPLOAD RAW   aws s3 sync brutos/<fonte> → s3://…/raw/<fonte>/ (STANDARD_IA)
3. VERIFY RAW   contagem de objetos local == remota; tamanho total confere
                (falha aqui ABORTA antes de qualquer exclusão)
4. TRANSFORM    Rscript 02_tratamento_<fonte>.R → tratados/<fonte>/
5. UPLOAD CURATED  aws s3 sync tratados/<fonte> → s3://…/curated/<fonte>/
6. METADATA     scripts/gen-schema.py gera <fonte>.schema.json
                (colunas, tipos, exemplo, nº linhas, bytes, SHA-256,
                descrição/periodicidade de scripts/metadados-fontes.json)
                → upload s3://…/metadata/<fonte>/<fonte>.schema.json
7. MANIFEST     append em manifest/manifest-<data>.csv (dataset, arquivo,
                bytes, sha256) → upload S3 (substitui o do dia)
8. CLEANUP      rm -rf brutos/<fonte> tratados/<fonte> locais
                (somente após passos 2-7 sem erro; log do que foi liberado)
```

**Verificação antes do cleanup (não-negociável):** objeto por objeto do lote,
`stat` local × `HeadObject` remoto (bytes). Divergência = abort sem excluir.
O versionamento do bucket permite recuperar uploads anteriores.

---

## 6. Metadata e Schema (formato)

Um JSON por fonte em `metadata/<fonte>/<fonte>.schema.json`:

```json
{
  "dataset": "ibge_pib_municipal",
  "descricao": "PIB municipal IBGE (SIDRA 5938)",
  "orgao": "IBGE",
  "periodicidade": "anual",
  "cobertura_temporal": "2002-2023",
  "tabela_glue": "ibge_pib_municipal_municipal",
  "arquivo": "curated/ibge_pib_municipal/ibge_pib_municipal_municipal.csv",
  "bytes": 9359419,
  "sha256": "83fc07…76",
  "linhas": 122466,
  "gerado_em": "2026-09-30T02:00:00Z",
  "colunas": [
    {"nome": "codigo_municipio", "tipo": "string", "exemplo": "3550308"},
    {"nome": "pib", "tipo": "integer", "exemplo": "1066825105"}
  ]
}
```

- **Tipos** inferidos por amostragem (`integer`/`double`/`string`) — compatível
  com o padrão que já usamos no Glue (tudo `string` + OpenCSVSerde; o schema
  registra o tipo *lógico* para uso futuro).
- **Campos de negócio** (`descricao`, `orgao`, `periodicidade`) vêm de
  `scripts/metadados-fontes.json` (curadoria manual, um bloco por fonte) —
  o que a API `/datasets` e a doc Lovable consomem depois.
- **Uso posterior:** gerar tabelas Glue automaticamente, popular o catálogo da
  API sem redeploy, e a Fase 5 (provenance on-chain) lê o `sha256` daqui.

---

## 7. Ordem de execução e pico de disco

Lotes sequenciais; após cada fonte, cleanup libera o staging.

| Lote | Fontes | Pico /data (estimado) | Tempo |
|---|---|---|---|
| 1 | `ibge_populacao`, `datasus_populacao`, `ibge_censo_demografico`, `ipea_suicidios` | < 1 GB | ~15 min |
| 2 | `caged`, `sagicad_cadunico`, `senatran`, `anp`, `mtur`, `snis_sinisa` | 1-3 GB | 1-2 h |
| 3 | `bcb_estban`, `mapbiomas`, `ibge_agropecuaria`, `comex`, `siconfi`, `inep` (censo/IDEB) | 3-6 GB | 2-4 h |
| 4 | `anatel` (zip 1 GB + _Colunas extraídos) | ~2-4 GB | ~1 h |
| 5 | `inep`/enem (fatiado por ano: 1,6-4 GB/ano) | ≤ 5 GB/ano | por ano |
| 6 | `rais` (fatiado por ano: 1,5-3,9 GB/ano comprimidos) | ≤ 5 GB/ano | por ano |

**Fatiamento das pesadas (RAIS/ENEM):** os scripts usam `ANO_INICIAL`; para
processar um ano por vez, patch pontual de `ANO_FINAL <- Sys.getenv("ANO_FINAL")`
na fonte (2 linhas) OU baixar em ordem crescente com cleanup anual — o pipeline
trata cada ano como um "lote" pela idempotência. **Sem o patch, RAIS completo
não cabe em 20 GB** (exige ~40 GB). Recomendo o patch antes do Lote 6.

**SNIS:** série histórica 2000-2022 exige exportação manual na aplicação do
governo (sem download em massa) — lote 2 entra só com SINISA 2023+ se os
brutos manuais não estiverem presentes; documentado no README da fonte.

**Estimativa de custo S3:** brutos ~65 GB em STANDARD_IA ≈ US$ 0,8/mês;
curados ~2 GB STANDARD ≈ US$ 0,05/mês. Requisições e Athena: cents por lote.

---

## 8. Estrutura de arquivos criada

```
scripts/
  etl-fonte.sh            orquestrador genérico (1 fonte = 1 chamada)
  etl-lote.sh             driver: executa um lote (lista de fontes) em sequência
  gen-schema.py           gerador de <fonte>.schema.json a partir do CSV curado
  metadados-fontes.json   curadoria: descricao/orgao/periodicidade por fonte
docs/etl/
  ETL-EXTRACAO-S3-PLANO.md   (este documento)
```

Uso:

```bash
bash scripts/etl-fonte.sh ibge_populacao          # uma fonte (ciclo completo)
bash scripts/etl-lote.sh lote1                    # lote 1 inteiro
PAINEL_ANO_INICIAL=2020 bash scripts/etl-fonte.sh caged   # recorte de teste
```

Idempotente: fonte já 100% no S3 (checagem por manifest) é pulada com aviso.

---

## 9. Fases futuras (fora do escopo deste plano)

- **Glue automático:** job que lê `metadata/*.schema.json` e cria/atualiza
  tabelas Glue (substitui a criação manual do CDK atual).
- **API dinâmica:** `/datasets` passa a ler o `metadata/` do S3 — fonte nova
  aparece na API sem redeploy.
- **Fase 5 (provenance):** `sha256` do schema JSON → registro on-chain Solana
  (programa `dataset_provenance`, devnet) quando o faucet destravar.
- **Doc Lovable:** páginas de dataset geradas a partir do mesmo JSON.

---

## 10. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| /data encher no meio do lote | pico por fonte < 6 GB exceto fatiáveis; monitor `df` no início de cada ciclo; aborta com >90% |
| Fonte muda layout/endpoint | brutos preservados em `raw/` permitem reprocessar sem re-download |
| Upload parcial/corrompido | verificação objeto-a-objeto antes do cleanup; versionamento S3 |
| Limpeza acidental indevida | cleanup só no fim do ciclo, só das pastas da fonte, nunca do staging inteiro |
| Faucet/fonte fora do ar | ciclo é retomável; re-execução pula o que já subiu |