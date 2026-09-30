#!/usr/bin/env python3
"""Fase 4: Lambda handler da API de dados municipais (token-gated).

Endpoints (via API Gateway):
  GET /datasets                        -> catalogo de datasets
  GET /datasets/{dataset}/query?municipio=&uf=&ano=&limit=

Auth: header Authorization: Bearer <token>. Tokens emitidos pela camada de
pagamento (fase 3 do produto: pagamento crypto -> token). Nesta fase de teste,
um token de teste hardcoded em Secrets Manager.

Queries via Athena sobre Glue table externa apontando para s3://colosseum-dados-municipais-dev/curated/.
"""
import json
import os
import time
import urllib.parse
import uuid

import boto3

ATHENA = boto3.client("athena")
GLUE = boto3.client("glue")
SECRETS = boto3.client("secretsmanager")

DATABASE = "dados_municipais"
WORKGROUP = "primary"
TOKEN_SECRET_ARN = os.environ.get("TOKEN_SECRET_ARN", "")
DATASETS = {
    "ibge_pib_municipal": {
        "tabela": "ibge_pib_municipal_municipal",
        "periodicidade": "anual",
        "descricao": "PIB municipal IBGE (SIDRA 5938), 2002-2023, valores em milhares de R$",
    },
    "sagicad_bolsa_familia": {
        "tabela": "sagicad_bolsa_familia_municipal",
        "periodicidade": "mensal",
        "descricao": "Bolsa Familia/Auxilio Brasil por municipio (MISocial/MDS), 2004-2026",
    },
}
ALLOWED_TABLES = {d["tabela"]: k for k, d in DATASETS.items()}


def _check_token(event):
    """Valida Bearer token contra o valor em Secrets Manager. Retorna claims ou None."""
    if not TOKEN_SECRET_ARN:
        return None
    auth = (event.get("headers") or {}).get("authorization", "") or (event.get("headers") or {}).get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    token = auth[7:].strip()
    try:
        secret = json.loads(SECRETS.get_secret_value(SecretId=TOKEN_SECRET_ARN)["SecretString"])
    except Exception:
        return None
    if token != secret.get("token"):
        return None
    claims = json.loads(secret.get("claims", "{}"))
    claims.setdefault("datasets", list(DATASETS.keys()))
    return claims


def _athena_query(sql, max_rows=1000):
    """Executa query Athena e retorna linhas como list de dict."""
    qid = ATHENA.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": DATABASE},
        WorkGroup=WORKGROUP,
        ResultConfiguration={"OutputLocation": "s3://athena-results-colosseum-dev/"},
    )["QueryExecutionId"]
    state = "RUNNING"
    for _ in range(60):  # ate ~30s
        state = ATHENA.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(0.5)
    if state != "SUCCEEDED":
        reason = ATHENA.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"].get("StateChangeReason", state)
        raise RuntimeError(f"Athena {state}: {reason}")
    rows = []
    paginator = ATHENA.get_paginator("get_query_results")
    for page in paginator.paginate(QueryExecutionId=qid):
        header = [c["Name"] for c in page["ResultSet"]["ResultSetMetadata"]["ColumnInfo"]]
        for r in page["ResultSet"]["Rows"][1 if not rows else 0:]:
            rows.append(dict(zip(header, [v.get("VarCharValue") for v in r["Data"]])))
        if len(rows) >= max_rows:
            break
    return rows[:max_rows]


def _json(status, body):
    return {"statusCode": status, "headers": {"Content-Type": "application/json"},
            "body": json.dumps(body, ensure_ascii=False)}


def handler(event, context):
    claims = _check_token(event)
    if claims is None:
        return _json(401, {"error": "token invalido ou ausente", "hint": "pagamento crypto emite token (fase 3 do produto)"})
    path = event.get("rawPath") or event.get("path", "")
    parts = [p for p in path.split("/") if p]
    method = event.get("requestContext", {}).get("http", {}).get("method") or event.get("httpMethod", "GET")

    if parts == ["datasets"]:
        return _json(200, {"datasets": DATASETS, "claims": claims.get("datasets")})

    # /datasets/{dataset}/query
    if len(parts) >= 3 and parts[0] == "datasets":
        dataset = parts[1]
        if dataset not in DATASETS:
            return _json(404, {"error": f"dataset '{dataset}' desconhecido", "disponiveis": list(DATASETS.keys())})
        if dataset not in (claims.get("datasets") or []):
            return _json(403, {"error": f"token nao autorizado para '{dataset}'"})
        if method != "GET":
            return _json(405, {"error": "somente GET"})
        params = {k: v for k, v in [p.split("=", 1) for p in
                                     (event.get("rawQueryString") or "").split("&") if p and "=" in p]}
        params = {k: urllib.parse.unquote(v) for k, v in params.items()}

        where = []
        limit = min(int(params.get("limit", 1000)), 10000)
        safe = lambda v: str(v).replace("'", "''")[:64]
        if params.get("municipio"):
            where.append(f"codigo_municipio = '{safe(params['municipio'])}'")
        if params.get("uf"):
            where.append(f"uf = '{safe(params['uf'])}'")
        if params.get("ano"):
            where.append(f"ano = {safe(params['ano'])}")
        if params.get("ano_inicio") and params.get("ano_fim"):
            where.append(f"ano BETWEEN {safe(params['ano_inicio'])} AND {safe(params['ano_fim'])}")
        sql = f"SELECT * FROM {DATASETS[dataset]['tabela']}"
        if where:
            sql += " WHERE " + " AND ".join(where)
        sql += f" LIMIT {limit}"
        try:
            rows = _athena_query(sql, limit)
        except Exception as e:
            return _json(500, {"error": str(e)[:300]})
        return _json(200, {"dataset": dataset, "rows": len(rows), "data": rows})

    return _json(404, {"error": "rota desconhecida", "rotas": ["GET /datasets", "GET /datasets/{dataset}/query"]})