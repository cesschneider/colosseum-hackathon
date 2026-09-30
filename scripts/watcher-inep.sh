#!/bin/bash
# Watcher: aguarda o siconfi concluir (processo some) e lanca o inep SEM enem
# (enem ~10GB brutos nao cabe no staging agora; entra fatiado no lote 5).
while pgrep -f "etl-fonte.sh siconfi" > /dev/null; do sleep 60; done
echo "=== INEP (sem enem) INICIO $(date) ===" >> /data/colosseum/logs/etl-execucao.log
cd /root/projects/colosseum-hackathon
PAINEL_INEP_FLUXOS="censo_escolar,taxas_rendimento,ideb_municipios" bash scripts/etl-fonte.sh inep >> /data/colosseum/logs/etl-execucao.log 2>&1
echo "EXIT inep-sem-enem=$?" >> /data/colosseum/logs/etl-execucao.log
echo "=== INEP (sem enem) FIM $(date) ===" >> /data/colosseum/logs/etl-execucao.log