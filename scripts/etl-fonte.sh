#!/bin/bash
# =============================================================================
# etl-fonte.sh — Ciclo ETL completo de UMA fonte (extracao -> S3 -> schema ->
#               manifest -> cleanup). Pipeline generica: qualquer fonte do
#               repositorio entra aqui sem codigo novo.
# Uso:
#   bash scripts/etl-fonte.sh <fonte>            # ciclo completo
#   PAINEL_ANO_INICIAL=2020 bash scripts/etl-fonte.sh <fonte>   # recorte
# Requer: AWS_PROFILE com acesso ao bucket; Rscript no PATH.
# Staging: /data/colosseum/staging (PAINEL_DADOS) — volume TEMPORARIO.
# =============================================================================
set -euo pipefail

FONTE="${1:?Uso: etl-fonte.sh <fonte>}"
export AWS_PROFILE="${AWS_PROFILE:-eworks-dev}"
BUCKET="${BUCKET:-colosseum-dados-municipais-dev}"
STAGING="${PAINEL_DADOS:-/data/colosseum/staging}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$REPO/dados-municipais"   # raiz do pipeline R (contem fontes/00_comum)
DATE=$(date +%Y%m%d)

log() { echo -e "\n[$(date +%H:%M:%S)] === $* ==="; }
die() { echo "ABORTADO: $*" >&2; exit 1; }

# --- 0. pre-condicoes ---------------------------------------------------------
log "0/8 pre-condicoes: $FONTE"
[ -d "$ROOT/fontes/$FONTE" ] || die "fonte inexistente: $ROOT/fontes/$FONTE"
command -v Rscript >/dev/null || die "Rscript ausente"
DISP=$(df --output=avail -m /data | tail -1)
[ "$DISP" -lt 5000 ] && die "menos de 5GB livres no /data ($DISP MB) — rode df/limpeza"

# --- 1. EXTRACT --------------------------------------------------------------
log "1/8 extracao (brutos -> $STAGING/brutos/$FONTE)"
export PAINEL_DADOS="$STAGING"
export PAINEL_PROJETO="colosseum-etl"
Rscript "$ROOT/fontes/$FONTE/01_extracao_$FONTE.R"

# --- 2. UPLOAD RAW -----------------------------------------------------------
log "2/8 upload raw -> s3://$BUCKET/raw/$FONTE/"
aws s3 sync "$STAGING/brutos/$FONTE" "s3://$BUCKET/raw/$FONTE/" --storage-class STANDARD_IA

# --- 3. VERIFY RAW (objeto a objeto ANTES de qualquer exclusao) ---------------
log "3/8 verificacao raw"
N_LOCAL=$(find "$STAGING/brutos/$FONTE" -type f | wc -l)
N_S3=$(aws s3 ls "s3://$BUCKET/raw/$FONTE/" --recursive | wc -l)
[ "$N_LOCAL" -eq "$N_S3" ] || die "raw: $N_LOCAL locais x $N_S3 remotos"
BYTES_LOCAL=$(find "$STAGING/brutos/$FONTE" -type f -printf '%s\n' | awk '{s+=$1} END {print s+0}')
BYTES_S3=$(aws s3 ls "s3://$BUCKET/raw/$FONTE/" --recursive | awk '{s+=$3} END {print s+0}')
[ "$BYTES_LOCAL" -eq "$BYTES_S3" ] || die "raw bytes: $BYTES_LOCAL locais x $BYTES_S3 remotos"
echo "raw ok: $N_LOCAL objetos, $BYTES_LOCAL bytes"

# --- 4. TRANSFORM ------------------------------------------------------------
log "4/8 tratamento -> $STAGING/tratados/$FONTE"
Rscript "$ROOT/fontes/$FONTE/02_tratamento_$FONTE.R"

# --- 5. UPLOAD CURATED -------------------------------------------------------
log "5/8 upload curated -> s3://$BUCKET/curated/$FONTE/"
aws s3 sync "$STAGING/tratados/$FONTE" "s3://$BUCKET/curated/$FONTE/" --storage-class STANDARD

# --- 6. METADATA / SCHEMA ----------------------------------------------------
log "6/8 schema JSON -> s3://$BUCKET/metadata/$FONTE/"
for f in "$STAGING/tratados/$FONTE"/*.csv; do
  case "$(basename "$f")" in *_municipal.csv) python3 "$REPO/scripts/gen-schema.py" "$FONTE" "$f"; break;; esac
done
aws s3 sync "$STAGING/metadata/$FONTE" "s3://$BUCKET/metadata/$FONTE/" --storage-class STANDARD

# --- 7. MANIFEST (append diário; sha256 de TODOS os csv curados da fonte) ----
log "7/8 manifest manifest-$DATE.csv"
MANIFEST="$STAGING/manifest/manifest-$DATE.csv"
mkdir -p "$STAGING/manifest"
[ -f "$MANIFEST" ] || echo "dataset,arquivo,bytes,sha256" > "$MANIFEST"
grep -v "^$FONTE," "$MANIFEST" > "$MANIFEST.tmp" 2>/dev/null || cp "$MANIFEST" "$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"
for f in "$STAGING/tratados/$FONTE"/*.csv; do
  sha=$(sha256sum "$f" | awk '{print $1}')
  size=$(stat -c%s "$f")
  echo "$FONTE,$(basename "$f"),$size,$sha" >> "$MANIFEST"
done
aws s3 cp "$MANIFEST" "s3://$BUCKET/manifest/manifest-$DATE.csv"

# --- 8. CLEANUP (so apos 1-7 sem erro; so a fonte processada) ----------------
log "8/8 cleanup staging local"
LIB=$(du -sh "$STAGING/brutos/$FONTE" "$STAGING/tratados/$FONTE" 2>/dev/null | awk '{s+=$1} END {print s}')
rm -rf "$STAGING/brutos/$FONTE" "$STAGING/tratados/$FONTE"
echo "liberado: $LIB"

log "FONTE $FONTE CONCLUIDA"
echo "  raw:     s3://$BUCKET/raw/$FONTE/ ($N_LOCAL objetos)"
echo "  curated: s3://$BUCKET/curated/$FONTE/"
echo "  schema:  s3://$BUCKET/metadata/$FONTE/$FONTE.schema.json"
echo "  manifest: s3://$BUCKET/manifest/manifest-$DATE.csv"