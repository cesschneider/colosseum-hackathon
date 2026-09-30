#!/bin/bash
# =============================================================================
# etl-lote.sh — executa um LOTE de fontes em sequencia (etl-fonte.sh por fonte).
# Falha em uma fonte NAO interrompe as demais; resumo no fim.
# Uso:
#   bash scripts/etl-lote.sh lote1
#   bash scripts/etl-lote.sh ibge_populacao caged   # fontes explicitas
# =============================================================================
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

LOTES=(
  [lote1]="ibge_populacao datasus_populacao ibge_censo_demografico ipea_suicidios"
  [lote2]="caged sagicad_cadunico senatran anp mtur snis_sinisa"
  [lote3]="bcb_estban mapbiomas ibge_agropecuaria comex siconfi inep"
  [lote4]="anatel sim"
  # lotes 5/6 (enem/rais) sao fatiados por ano — ver docs/etl/ETL-EXTRACAO-S3-PLANO.md §7
)

if [ $# -eq 0 ]; then
  echo "Lotes definidos:"
  for k in lote1 lote2 lote3 lote4; do echo "  $k: ${LOTES[$k]}"; done
  exit 0
fi

if [ $# -eq 1 ] && [ -n "${LOTES[$1]:-}" ]; then
  read -ra FONTES <<< "${LOTES[$1]}"
else
  FONTES=("$@")
fi

ok=(); erro=()
for f in "${FONTES[@]}"; do
  echo -e "\n########## FONTE: $f ##########"
  if bash "$REPO/scripts/etl-fonte.sh" "$f"; then
    ok+=("$f")
  else
    erro+=("$f")
  fi
done

echo -e "\n===== RESUMO DO LOTE ====="
echo "OK:    ${ok[*]:-nenhuma}"
echo "ERRO:  ${erro[*]:-nenhuma}"
[ ${#erro[@]} -eq 0 ]