# STATUS DA EXTRAÇÃO — Pipeline ETL Dados Municipais

**Atualizado:** 2026-09-30 06:35 (-03) · **Execução:** YOLO automática
**Bucket:** `s3://colosseum-dados-municipais-dev` · **Staging:** `/data/colosseum/staging` (temporário, limpo por fonte)
**Log completo:** `/data/colosseum/logs/etl-execucao.log`

---

## Resumo por fonte (curados no S3)

| Fonte | Linhas | Curado (MB) | Colunas | Raw (MB) | Raw obj | Status |
|---|---|---|---|---|---|---|
| anatel | 105.509 | 10,4 | 16 | 1.000 | 3 | ✅ |
| anp | 74.388 | 7,4 | 13 | 2.150 | 63 | ✅ (fix zip Latin-1) |
| bcb_estban | 1.065.980 | 120,9 | 17 | 333 | 318 | ✅ |
| caged | 38.974 | 1,6 | 8 | 48 | 4 | ✅ |
| comex | 426.692 | 23,1 | 10 | 2.602 | 54 | ✅ (fix SSL Sectigo) |
| datasus_populacao | 144.821 | 16,6 | 12 | 10 | 26 | ✅ |
| ibge_agropecuaria | 257.427 | 22,5 | 16 | 5 | 5 | ✅ |
| ibge_censo_demografico | 16.642 | 2,0 | 23 | 1 | 7 | ✅ |
| ibge_populacao | 208.811 | 8,2 | 7 | 30 | 4 | ✅ |
| ibge_pib_municipal | 122.466 | 8,9 | 12 | — | — | ✅ (fases 1-3, 29/09) |
| ipea_suicidios | 200.929 | 6,5 | 6 | 47 | 4 | ✅ |
| mapbiomas | 228.370 | 45,4 | 17 | 74 | 1 | ✅ (fix zip Drive) |
| mtur | 39.102 | 1,5 | 8 | 172 | 42 | ✅ |
| sagicad_bolsa_familia | 1.519.903 | 161,5 | 15 | 90 | 18 | ✅ (fase 2, 29/09) |
| sagicad_cadunico | 941.248 | 81,5 | 15 | 97 | 12 | ✅ |
| senatran | 672.752 | 87,9 | 38 | 243 | 242 | ✅ |
| sim | 150.417 | 15,3 | 16 | 250 | 650 | ✅ (após install microdatasus) |
| snis_sinisa | 5.250 | 0,7 | 28 | 32 | 4 | ✅ (só SINISA 2023+; SNIS 2000-22 manual) |

**Totais até agora: 18 fontes · ~6,3M linhas curadas · ~625 MB curados · ~7,3 GB raw (STANDARD_IA)**

## Em andamento / pendentes

| Fonte | Situação |
|---|---|
| siconfi | 🔄 Rodando (~6h+): DCA concluída, agora RREO 2024 (~700/5570 entes); log em `etl-execucao.log` |
| inep (censo/ideb/rendimento) | ⏳ Fila após siconfi — **excluir fluxo `enem`** na 1ª passada (10 GB brutos) |
| inep/enem | ⏳ Fatiar por ano (1,6-4 GB/ano) |
| rais | ⏳ Fatiar por ano via `PAINEL_RAIS_ANO_FINAL` (1,5-3,9 GB/ano comprimido; exige 7z) |

## Bugs corrigidos durante a execução

1. **anp** — zips da ANP gravam nome interno em Latin-1; `list.files(pattern="[.]csv$")` não achava o arquivo extraído → patch no `02_tratamento_anp.R` (seleção tolerante de arquivos extraídos).
2. **mapbiomas** — Google Drive entrega um ZIP contendo o XLSX; script salvava o zip com extensão .xlsx ilegível → extração manual do xlsx real; retry OK.
3. **comex** — servidor `balanca.economia.gov.br` envia cadeia TLS incompleta (sem intermediário) → instalados intermediário Sectigo OV R36 + root R46; para o R usar `CURL_CA_BUNDLE=/etc/ssl/certs/sectigo-chain-economia.pem`.
4. **sim** — pacotes opcionais (`microdatasus`) não instalados → `instalar_dependencias.R --opcionais` em execução.

## Manifest e schemas

- Manifest do dia: `s3://colosseum-dados-municipais-dev/manifest/manifest-20260930.csv` (SHA-256 de cada curado)
- Schemas JSON por fonte: `s3://colosseum-dados-municipais-dev/metadata/<fonte>/<fonte>.schema.json` (colunas, tipos, linhas, bytes, SHA-256, curadoria)
- Estrutura por fonte no S3: `raw/<fonte>/` (imutável) · `curated/<fonte>/` · `metadata/<fonte>/`