#!/usr/bin/env python3
"""Fase 4: CDK stack — API de dados municipais token-gated.

Conforme plano docs/testing/TEST-PLAN-DADOS-MUNICIPAIS-E2E.md:
API Gateway HTTP -> Lambda (handler.py) -> Athena/Glue sobre o bucket
colosseum-dados-municipais-dev. Nada manual no console (regra CDK-only).

Deploy: cdk deploy DadosApiStack --require-approval never
"""
import boto3
import json
import secrets

from aws_cdk import (
    App, CfnOutput, Duration, Stack,
)
from aws_cdk import (
    aws_apigatewayv2 as apigwv2,
    aws_glue as glue,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_secretsmanager as sm,
)
from constructs import Construct

BUCKET = "colosseum-dados-municipais-dev"
REGION = "us-east-1"
ACCOUNT = "666637312477"


class DadosApiStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs):
        super().__init__(scope, construct_id, **kwargs)

        # --- Glue database + tabelas externas sobre o curated S3 ---
        # Banco Glue criado via CLI previamente (dependencia externa estavel);
        # recriado aqui apenas se ausente. Tabelas com depends_on explicito.
        glue_db_construct = glue.CfnDatabase(self, "DadosDb",
                         catalog_id=ACCOUNT,
                         database_input=glue.CfnDatabase.DatabaseInputProperty(name="dados_municipais"))
        glue_db = type("Ref", (), {"name": "dados_municipais"})()

        cols_pib = [
            glue.CfnTable.ColumnProperty(name="codigo_municipio", type="bigint"),
            glue.CfnTable.ColumnProperty(name="nome_municipio", type="string"),
            glue.CfnTable.ColumnProperty(name="uf", type="string"),
            glue.CfnTable.ColumnProperty(name="ano", type="int"),
            glue.CfnTable.ColumnProperty(name="pib", type="bigint"),
            glue.CfnTable.ColumnProperty(name="vab_total", type="bigint"),
            glue.CfnTable.ColumnProperty(name="vab_agropecuaria", type="bigint"),
            glue.CfnTable.ColumnProperty(name="vab_industria", type="bigint"),
            glue.CfnTable.ColumnProperty(name="vab_servicos", type="bigint"),
            glue.CfnTable.ColumnProperty(name="vab_adm_publica", type="bigint"),
            glue.CfnTable.ColumnProperty(name="impostos_liquidos", type="bigint"),
            glue.CfnTable.ColumnProperty(name="pib_per_capita", type="double"),
        ]
        bf_cols = [glue.CfnTable.ColumnProperty(name=n, type=t) for n, t in [
            ("codigo_municipio", "bigint"), ("nome_municipio", "string"), ("uf", "string"),
            ("ano", "int"), ("mes", "int"), ("familias_bolsa_familia", "bigint"),
            ("valor_bolsa_familia", "double"), ("familias_auxilio_brasil", "bigint"),
            ("valor_auxilio_brasil", "double"), ("familias_beneficiarias", "bigint"),
            ("valor_repassado", "double"), ("valor_medio_familia", "double"),
            ("populacao_estimada", "bigint"), ("familias_por_100_habitantes", "double"),
            ("valor_repassado_per_capita", "double"),
        ]]

        pib_table = glue.CfnTable(self, "PibTable",
                      catalog_id=ACCOUNT, database_name="dados_municipais",
                      table_input=glue.CfnTable.TableInputProperty(
                          name="ibge_pib_municipal_municipal",
                          storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                              columns=cols_pib,
                              location=f"s3://{BUCKET}/curated/ibge_pib_municipal/",
                              input_format="org.apache.hadoop.mapred.TextInputFormat",
                              output_format="org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
                              serde_info=glue.CfnTable.SerdeInfoProperty(
                                  serialization_library="org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
                                  parameters={"separatorChar": ",", "skip.header.line.count": "1"}),
                          ),
                          parameters={"classification": "csv"},
                      ))
        pib_table.add_depends_on(glue_db_construct)
        bf_table = glue.CfnTable(self, "BolsaFamiliaTable",
                      catalog_id=ACCOUNT, database_name="dados_municipais",
                      table_input=glue.CfnTable.TableInputProperty(
                          name="sagicad_bolsa_familia_municipal",
                          storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                              columns=bf_cols,
                              location=f"s3://{BUCKET}/curated/sagicad_bolsa_familia/",
                              input_format="org.apache.hadoop.mapred.TextInputFormat",
                              output_format="org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
                              serde_info=glue.CfnTable.SerdeInfoProperty(
                                  serialization_library="org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
                                  parameters={"separatorChar": ",", "skip.header.line.count": "1"}),
                          ),
                          parameters={"classification": "csv"},
                      ))
        bf_table.add_depends_on(glue_db_construct)

        # --- Token de teste (fase de pagamento depois) ---
        token = secrets.token_urlsafe(24)
        token_secret = sm.CfnSecret(self, "DadosApiToken",
                                   name="dados-api/test-token",
                                   secret_string=json.dumps({
                                       "token": token,
                                       "claims": json.dumps({"datasets": ["ibge_pib_municipal", "sagicad_bolsa_familia"]}),
                                   }))

        # --- Lambda ---
        fn = lambda_.Function(self, "DadosApiFn",
                              runtime=lambda_.Runtime.PYTHON_3_12,
                              handler="handler.handler",
                              code=lambda_.Code.from_asset("src"),
                              timeout=Duration.seconds(30),
                              memory_size=512,
                              environment={"TOKEN_SECRET_ARN": token_secret.ref})

        fn.add_to_role_policy(iam.PolicyStatement(
            actions=["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults",
                     "athena:GetWorkGroup", "athena:StopQueryExecution"],
            effect=iam.Effect.ALLOW, resources=["*"]))
        fn.add_to_role_policy(iam.PolicyStatement(
            actions=["glue:GetTable", "glue:GetDatabase", "glue:GetPartitions"],
            effect=iam.Effect.ALLOW, resources=["*"]))
        fn.add_to_role_policy(iam.PolicyStatement(
            actions=["secretsmanager:GetSecretValue"],
            effect=iam.Effect.ALLOW, resources=[token_secret.ref]))
        fn.add_to_role_policy(iam.PolicyStatement(
            actions=["s3:GetObject", "s3:ListBucket"],
            effect=iam.Effect.ALLOW,
            resources=["arn:aws:s3:::athena-results-colosseum-dev/*", "arn:aws:s3:::athena-results-colosseum-dev",
                       f"arn:aws:s3:::{BUCKET}/*"]))
        fn.add_to_role_policy(iam.PolicyStatement(
            actions=["s3:GetBucketLocation"],
            effect=iam.Effect.ALLOW, resources=[f"arn:aws:s3:::{BUCKET}"]))
        # Athena grava resultados no bucket de resultados padrao do workgroup primary
        fn.add_to_role_policy(iam.PolicyStatement(
            actions=["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"],
            effect=iam.Effect.ALLOW,
            resources=[f"arn:aws:s3:::{BUCKET}/athena-results/*", "arn:aws:s3:::athena-results-colosseum-dev/*",
                       "arn:aws:s3:::athena-results-colosseum-dev", f"arn:aws:s3:::{BUCKET}"]))
        # Modo teste publico: sem exigencia de token (ligar REQUIRE_TOKEN=true em producao)
        fn.add_environment("REQUIRE_TOKEN", "false")

        # --- API Gateway HTTP ---
        api = apigwv2.CfnApi(self, "DadosApi", name="dados-municipais-api",
                             protocol_type="HTTP",
                             target=fn.function_arn)
        # Permissao para o API Gateway HTTP invocar a Lambda (target= so cria a
        # integracao; a resource policy precisa ser explicita)
        lambda_.CfnPermission(self, "DadosApiInvoke",
                              action="lambda:InvokeFunction",
                              function_name=fn.function_name,
                              principal="apigateway.amazonaws.com",
                              source_arn=f"arn:aws:execute-api:{REGION}:{ACCOUNT}:*/$default")
        CfnOutput(self, "ApiUrl", value=api.api_endpoint if hasattr(api, "api_endpoint") else "?")
        CfnOutput(self, "TokenSecret", value=token_secret.name)
        CfnOutput(self, "TestToken", value=token)  # visivel no output do deploy


app = App()
DadosApiStack(app, "DadosApiStack", env={"region": REGION, "account": ACCOUNT})
app.synth()