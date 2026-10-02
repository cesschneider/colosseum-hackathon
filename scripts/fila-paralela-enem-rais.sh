#!/usr/bin/env bash
# Fila SEQUENCIAL de fatias de anos (v3) — /data tem apenas ~8-10G livres
# (k3trunk 102G + docker 87G ocupam o volume), entao enem e rais NAO podem
# rodar simultaneos nem baixar series inteiras de uma vez.
#
# Cada fatia = 1 ciclo completo (extracao -> upload S3 -> schema -> cleanup),
# agora com limites REAIS de ano: PAINEL_ANO_INICIAL + PAINEL_ANO_FINAL.
# Ordem: siconfi ja roda em paralelo (API, ~400M). Depois enem (fatias de
# 3 anos, ~2-4G) e rais (fatias de 3 anos, ~4-6G) ALTERNADOS, um por vez.
set -u
cd /root/projects/colosseum-hackathon || exit 1
LOG=/data/colosseum/logs/etl-execucao.log

run_enem() {  # $1 ini  $2 fim
  echo "[$(date '+%H:%M:%S')] [enem] fatia $1-$2 INICIO" >> "$LOG"
  PAINEL_INEP_FLUXOS="enem" PAINEL_ANO_INICIAL=$1 PAINEL_ANO_FINAL=$2 \
    bash scripts/etl-fonte.sh inep >> "$LOG" 2>&1
  echo "[enem] fatia $1-$2 EXIT=$?" >> "$LOG"
}

run_rais() {  # $1 ini  $2 fim
  echo "[$(date '+%H:%M:%S')] [rais] fatia $1-$2 INICIO" >> "$LOG"
  PAINEL_ANO_INICIAL=$1 PAINEL_RAIS_ANO_FINAL=$2 \
    bash scripts/etl-fonte.sh rais >> "$LOG" 2>&1
  echo "[rais] fatia $1-$2 EXIT=$?" >> "$LOG"
}

echo "=== FILA v3 FATIAS SEQ INICIO $(date) ===" >> "$LOG"

# ENEM 2009-2025 em fatias de 3 anos (zips de 0.5-1.1 GB/ano, ~2-4 GB/fatia)
run_enem 2009 2011
run_enem 2012 2014
run_enem 2015 2017
run_enem 2018 2020
run_enem 2021 2023
run_enem 2024 2025

# RAIS 2010-2025 em fatias de 3 anos (7z de 1.5-4 GB/fatia)
run_rais 2010 2012
run_rais 2013 2015
run_rais 2016 2018
run_rais 2019 2021
run_rais 2022 2025

echo "=== FILA v3 FATIAS SEQ FIM $(date) ===" >> "$LOG"