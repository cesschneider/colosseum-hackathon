#!/usr/bin/env python3
"""Gera <fonte>.schema.json a partir do CSV curado de uma fonte.

Uso: python3 scripts/gen-schema.py <fonte> <caminho_csv_tratado> [<csv_dicionario>]

Le o CSV curado (amostra das primeiras 2000 linhas para inferir tipos), calcula
bytes, sha256 e numero de linhas totais, mescla com a curadoria de
scripts/metadados-fontes.json e grava em <staging>/metadata/<fonte>/<fonte>.schema.json.
"""
import csv
import hashlib
import json
import os
import sys
from datetime import datetime, timezone


def infer_tipo(valores: list) -> str:
    for v in valores:
        v = (v or "").strip()
        if not v:
            continue
        try:
            int(v)
            continue
        except ValueError:
            pass
        try:
            float(v.replace(",", "."))
            continue
        except ValueError:
            return "string"
    # so inteiros validos (ou vazio): checar se algum tinha separador decimal
    has_decimal = any(
        "." in (v or "") or "," in (v or "") for v in valores if (v or "").strip()
    )
    return "double" if has_decimal else "integer"


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    fonte, csv_path = sys.argv[1], sys.argv[2]
    meta_dir = os.path.dirname(os.path.abspath(__file__))
    staging = os.environ.get("PAINEL_DADOS", "/data/colosseum/staging")

    # curadoria
    curadoria = {}
    try:
        with open(os.path.join(meta_dir, "metadados-fontes.json"), encoding="utf-8") as f:
            curadoria = json.load(f)
    except FileNotFoundError:
        pass
    info = curadoria.get(fonte, {})

    # bytes + sha256
    h = hashlib.sha256()
    n_linhas = 0
    with open(csv_path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    bytes_arquivo = os.path.getsize(csv_path)

    # linhas + amostra
    with open(csv_path, encoding="utf-8", newline="") as f:
        rdr = csv.DictReader(f)
        colunas = []
        amostra = []
        for i, row in enumerate(rdr):
            n_linhas += 1
            if i < 2000:
                amostra.append(row)
        nomes = rdr.fieldnames or []

    for nome in nomes:
        vals = [r.get(nome, "") for r in amostra]
        exemplo = next((v for v in vals if (v or "").strip()), "")
        colunas.append({"nome": nome, "tipo": infer_tipo(vals), "exemplo": exemplo[:50]})

    schema = {
        "dataset": fonte,
        "descricao": info.get("descricao", ""),
        "orgao": info.get("orgao", ""),
        "periodicidade": info.get("periodicidade", ""),
        "cobertura_temporal": info.get("cobertura_temporal", ""),
        "tabela_glue": info.get("tabela_glue", f"{fonte}_municipal"),
        "arquivo": csv_path,
        "bytes": bytes_arquivo,
        "sha256": h.hexdigest(),
        "linhas": n_linhas,
        "gerado_em": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "colunas": colunas,
    }

    out_dir = os.path.join(staging, "metadata", fonte)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{fonte}.schema.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(schema, f, ensure_ascii=False, indent=2)
    print(f"schema: {out} ({len(colunas)} colunas, {n_linhas} linhas, {bytes_arquivo} bytes)")
    print(f"sha256: {h.hexdigest()}")


if __name__ == "__main__":
    main()