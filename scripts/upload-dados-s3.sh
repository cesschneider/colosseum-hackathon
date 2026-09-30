#!/bin/bash
# Fase 3 + 5: ingestao S3 (bucket dedicado) + SHA-256 dos datasets curados
# Uso: bash scripts/upload-dados-s3.sh
set -euo pipefail
export AWS_PROFILE=eworks-dev
BUCKET="colosseum-dados-municipais-dev"
REGION="us-east-1"
BASE="/root/projects/colosseum-hackathon/dados-municipais/dados"
DATE=$(date +%Y%m%d)

# 1. Criar bucket (idempotente) com versionamento + SSE-S3 + public access block
aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null || echo "bucket ja existe"
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 2. Upload raw (brutos preservados)
aws s3 sync "$BASE/brutos" "s3://$BUCKET/raw/" --storage-class STANDARD_IA
# 3. Upload curated (tratados + dicionarios)
aws s3 sync "$BASE/tratados" "s3://$BUCKET/curated/" --storage-class STANDARD
# 4. Catalogo: dicionario municipios
aws s3 cp "$BASE/auxiliares/dicionario_municipios.csv" "s3://$BUCKET/catalog/dicionario_municipios.csv"

# 5. SHA-256 dos curados (manifest p/ provenance on-chain fase 5)
mkdir -p "$BASE/manifest"
: > "$BASE/manifest/manifest-$DATE.csv"
echo "dataset,arquivo,bytes,sha256" >> "$BASE/manifest/manifest-$DATE.csv"
for f in "$BASE/tratados"/*/*.csv; do
  sha=$(sha256sum "$f" | awk '{print $1}')
  size=$(stat -c%s "$f")
  echo "$(basename $(dirname $f)),$(basename $f),$size,$sha" >> "$BASE/manifest/manifest-$DATE.csv"
done
aws s3 cp "$BASE/manifest/manifest-$DATE.csv" "s3://$BUCKET/manifest/manifest-$DATE.csv"
echo "=== MANIFEST ==="
cat "$BASE/manifest/manifest-$DATE.csv"
echo "=== CONTAGEM S3 ==="
aws s3 ls "s3://$BUCKET/raw/" --recursive | wc -l
aws s3 ls "s3://$BUCKET/curated/" --recursive | wc -l
aws s3 ls "s3://$BUCKET/" --recursive | wc -l