# Brainstorm: Passo 2 — Arquitetura Técnica Detalhada (MVP Dados)

**Autor:** @architect  
**Data:** 21 Set 2026  
**Foco:** Stack técnico, data model, deployment

---

## 1. Tech Stack Decision Matrix

| Camada | Opção | Decision | Rationale |
|--------|-------|----------|-----------|
| **Ingestão** | Lambda + EventBridge | ✅ AWS | Cesar domina CDK; sem server management |
| **Data Lake** | S3 + Parquet | ✅ AWS | Escalável, baixo custo, integração Athena |
| **Querying** | Athena | ✅ AWS | SQL direto em S3, sem ETL separado |
| **API Gateway** | API Gateway REST | ✅ AWS | Nativo, integração com Lambda, CORS built-in |
| **REST Backend** | Lambda + Node.js | ✅ AWS | Serverless, sem ops, escalável automaticamente |
| **Frontend** | Next.js + Recharts | ✅ Vercel | Deploy automático, ISR (Incremental Static Regen), charts simples |
| **Auth** | JWT + Lambda middleware | ✅ Custom | MVP simples; evita Cognito overhead |
| **Database** | PostgreSQL RDS | ⚠️ Opcional | Apenas se precisar estado (usuários, alertas). MVP: S3-only |
| **Monitoring** | CloudWatch + SNS | ✅ AWS | Logs centralizados, alertas de falhas de ingestão |
| **CI/CD** | GitHub Actions | ✅ Free | Já usamos; CDK deploy automático |

---

## 2. Arquitetura Detalhada (Diagrama ASCII)

```
┌─────────────────────────────────────────────────────────────────┐
│                      PUBLIC INTERNET                             │
│  IBGE API | ANP Dados.Gov | World Bank Commodities | RAIS         │
└────────────────────────────┬────────────────────────────────────┘
                             │ 
                      ┌──────▼──────┐
                      │ EventBridge │ (Cron scheduler)
                      │  every 2h   │
                      └──────┬──────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼────┐          ┌────▼────┐         ┌────▼────┐
   │ Lambda 1 │          │ Lambda 2 │         │ Lambda 3 │
   │ Ingest   │          │ Ingest   │         │ Ingest   │
   │ IPCA     │          │ ANP      │         │ Commodities
   │ (weekly) │          │ (daily)  │         │ (4h)
   └────┬────┘          └────┬────┘         └────┬────┘
        │                    │                    │
        │ Parse JSON       │ Scrape/Parse     │ Call API
        │ Enrich (BRL)     │ Normalize        │ Convert USD→BRL
        │ Validate         │ Join with hist   │ Validation
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                      ┌──────▼──────┐
                      │  S3 Bucket  │
                      │ (Data Lake) │
                      │ /inflation/ │
                      │ /fuel/      │
                      │ /commodities│
                      │ (Parquet)   │
                      └──────┬──────┘
                             │
                      ┌──────▼──────┐
                      │   Athena    │
                      │  SQL Engine │
                      │  (on-demand)│
                      └──────┬──────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼────────┐      ┌────▼────────┐    ┌────▼──────┐
   │  Lambda API │      │  Lambda API  │    │ Lambda API │
   │  GET /data  │      │ GET /stats   │    │ POST /alert
   │  (raw)      │      │ (aggregated) │    │ (notify)
   └────┬────────┘      └────┬────────┘    └────┬──────┘
        │                    │                   │
        └────────────────────┼───────────────────┘
                             │
                      ┌──────▼──────┐
                      │ API Gateway │
                      │ REST Routes │
                      └──────┬──────┘
                             │
                      ┌──────▼──────┐
                      │  Frontend   │
                      │  Next.js    │
                      │  (Vercel)   │
                      │  Dashboard  │
                      │  + Charts   │
                      └─────────────┘
```

---

## 3. CDK Infrastructure (TypeScript)

### Project Structure
```
colosseum-hackathon/
├── infra/
│   ├── lib/
│   │   ├── data-lake-stack.ts       # S3 + IAM roles
│   │   ├── ingest-stack.ts          # Lambda + EventBridge
│   │   ├── api-stack.ts             # API Gateway + Lambda
│   │   └── colosseum-stack.ts       # Root stack
│   ├── lambda/
│   │   ├── ingest-ipca/index.ts
│   │   ├── ingest-fuel/index.ts
│   │   ├── ingest-commodities/index.ts
│   │   ├── api-data/index.ts
│   │   ├── api-stats/index.ts
│   │   └── auth/jwt-middleware.ts
│   └── cdk.json
├── api/
│   ├── src/
│   │   ├── handlers/
│   │   ├── types/
│   │   └── utils/
│   └── package.json
├── frontend/
│   ├── pages/
│   ├── components/
│   └── package.json
└── docs/
    └── brainstorming/
        └── PASSO-2-MVP-DADOS-BRAINSTORM.md (este arquivo)
```

### data-lake-stack.ts
```typescript
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';

export class DataLakeStack extends cdk.Stack {
  public readonly bucket: s3.Bucket;

  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // S3 bucket with versioning + lifecycle
    this.bucket = new s3.Bucket(this, 'Colosseum-DataLake', {
      bucketName: `colosseum-data-lake-${this.account}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          // Archive old Parquet to Glacier after 90 days
          transitions: [
            {
              transitionAfter: cdk.Duration.days(90),
              storageClass: s3.StorageClass.GLACIER
            }
          ]
        }
      ]
    });

    // Partitions: /inflation/year=2024/month=01/, /fuel/year=2024/month=01/, etc.
  }
}
```

### ingest-stack.ts
```typescript
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';

export class IngestStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const dataLakeStack = new DataLakeStack(this, 'DataLake');

    // Lambda: Ingest IPCA (weekly, Mondays 2 AM UTC)
    const ingestIpca = new lambda.Function(this, 'IngestIpca', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('lambda/ingest-ipca'),
      environment: {
        BUCKET_NAME: dataLakeStack.bucket.bucketName
      },
      timeout: cdk.Duration.minutes(5)
    });

    dataLakeStack.bucket.grantWrite(ingestIpca);

    new events.Rule(this, 'IngestIpcaSchedule', {
      schedule: events.Schedule.cron({ minute: '0', hour: '2', weekDay: '1' }),
      targets: [new targets.LambdaFunction(ingestIpca)]
    });

    // Repeat for other Lambdas (Fuel, Commodities, Labor)
  }
}
```

### api-stack.ts
```typescript
import * as cdk from 'aws-cdk-lib';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as lambda from 'aws-cdk-lib/aws-lambda';

export class ApiStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const api = new apigateway.RestApi(this, 'ColossiumApi', {
      restApiName: 'Colosseum Data API',
      endpointTypes: [apigateway.EndpointType.REGIONAL]
    });

    // GET /api/v1/datasets/{datasetId}/data
    const datasetResource = api.root
      .addResource('api')
      .addResource('v1')
      .addResource('datasets')
      .addResource('{datasetId}')
      .addResource('data');

    const apiDataLambda = new lambda.Function(this, 'ApiData', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('lambda/api-data'),
      environment: {
        ATHENA_DATABASE: 'colosseum_data',
        ATHENA_BUCKET: 's3://colosseum-results/'
      }
    });

    datasetResource.addMethod('GET', new apigateway.LambdaIntegration(apiDataLambda), {
      requestParameters: {
        'method.request.querystring.from': true,
        'method.request.querystring.to': true
      }
    });

    // POST /api/v1/datasets/{datasetId}/alert
    const alertResource = api.root
      .addResource('api')
      .addResource('v1')
      .addResource('datasets')
      .addResource('{datasetId}')
      .addResource('alert');

    const apiAlertLambda = new lambda.Function(this, 'ApiAlert', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('lambda/api-alert')
    });

    alertResource.addMethod('POST', new apigateway.LambdaIntegration(apiAlertLambda));
  }
}
```

---

## 4. Data Model (Parquet Schema)

### inflation_ipca
```sql
-- Athena DDL
CREATE EXTERNAL TABLE IF NOT EXISTS colosseum_data.inflation_ipca (
  month DATE COMMENT 'Month in YYYY-MM-DD format',
  rate_12m_pct DECIMAL(10, 2) COMMENT 'Accumulated 12-month inflation %',
  rate_month_pct DECIMAL(10, 2) COMMENT 'Monthly inflation %',
  category_breakdown STRUCT<
    food: DECIMAL(10,2),
    fuel: DECIMAL(10,2),
    clothing: DECIMAL(10,2),
    housing: DECIMAL(10,2)
  >,
  data_source STRING COMMENT 'IBGE',
  ingested_at TIMESTAMP COMMENT 'Ingest timestamp'
)
PARTITIONED BY (year INT, month_num INT)
STORED AS PARQUET
LOCATION 's3://colosseum-data-lake/inflation/'
```

### fuel_prices_anp
```sql
CREATE EXTERNAL TABLE IF NOT EXISTS colosseum_data.fuel_prices_anp (
  date DATE,
  state VARCHAR(2),
  fuel_type VARCHAR(20), -- gasolina_comum, diesel, etanol
  avg_price_brl DECIMAL(10, 2),
  price_change_pct DECIMAL(10, 2),
  data_source STRING
)
PARTITIONED BY (year INT, month_num INT, week INT)
STORED AS PARQUET
LOCATION 's3://colosseum-data-lake/fuel/'
```

---

## 5. Lambda Function Example: Ingest IPCA

### lambda/ingest-ipca/index.ts
```typescript
import AWS from 'aws-sdk';
import axios from 'axios';
import * as parquet from 'parquetjs';

const s3 = new AWS.S3();

export async function handler(event: any) {
  try {
    // 1. Fetch IBGE data
    const response = await axios.get(
      'https://servicodados.ibge.gov.br/api/v3/agregados/8654/periodos/-12/variaveis/63'
    );
    const ipcaData = response.data.resultados[0].series[0].dado;

    // 2. Transform to Parquet schema
    const records = Object.entries(ipcaData).map(([month, value]: [string, any]) => ({
      month: new Date(`${month.substring(0, 4)}-${month.substring(4, 6)}-01`),
      rate_12m_pct: parseFloat(value),
      rate_month_pct: null, // TODO: fetch separately
      category_breakdown: {
        food: null,
        fuel: null,
        clothing: null,
        housing: null
      },
      data_source: 'IBGE',
      ingested_at: new Date()
    }));

    // 3. Write to Parquet (S3)
    const schema = new parquet.ParquetSchema({
      month: { type: 'UTF8', optional: false },
      rate_12m_pct: { type: 'DOUBLE', optional: false },
      data_source: { type: 'UTF8', optional: false },
      ingested_at: { type: 'TIMESTAMP_MILLIS', optional: false }
    });

    const writer = await parquet.ParquetWriter.openFile(
      schema,
      `/tmp/inflation-${Date.now()}.parquet`
    );
    
    for (const record of records) {
      await writer.appendRow(record);
    }
    await writer.close();

    // 4. Upload to S3 with partition keys
    const today = new Date();
    const year = today.getFullYear();
    const month = String(today.getMonth() + 1).padStart(2, '0');

    await s3.upload({
      Bucket: process.env.BUCKET_NAME!,
      Key: `inflation/year=${year}/month=${month}/inflation-${Date.now()}.parquet`,
      Body: require('fs').readFileSync(`/tmp/inflation-${Date.now()}.parquet`)
    }).promise();

    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'IPCA ingested successfully',
        recordsCount: records.length
      })
    };
  } catch (error) {
    console.error('Ingest failed:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: (error as Error).message })
    };
  }
}
```

---

## 6. API Lambda: GET /data

### lambda/api-data/index.ts
```typescript
import AWS from 'aws-sdk';

const athena = new AWS.Athena();

export async function handler(event: any) {
  const { datasetId } = event.pathParameters;
  const { from, to } = event.queryStringParameters || {};

  try {
    // 1. Validate JWT (TODO: implement JWT middleware)
    // const scope = validateJWT(event.headers.Authorization);

    // 2. Map datasetId to Athena table
    const tableMap: Record<string, string> = {
      'inflation': 'colosseum_data.inflation_ipca',
      'fuel': 'colosseum_data.fuel_prices_anp',
      'commodities': 'colosseum_data.commodity_prices',
      'labor': 'colosseum_data.labor_market_caged'
    };

    const table = tableMap[datasetId];
    if (!table) {
      return { statusCode: 404, body: JSON.stringify({ error: 'Dataset not found' }) };
    }

    // 3. Build Athena query
    const query = `
      SELECT * FROM ${table}
      WHERE month >= CAST('${from}' AS DATE)
        AND month <= CAST('${to}' AS DATE)
      ORDER BY month DESC
      LIMIT 1000
    `;

    // 4. Execute query
    const result = await executeAthenaQuery(query);

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        dataset_id: datasetId,
        data: result,
        metadata: {
          last_updated: new Date().toISOString(),
          record_count: result.length
        }
      })
    };
  } catch (error) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: (error as Error).message })
    };
  }
}

async function executeAthenaQuery(query: string): Promise<any[]> {
  // TODO: Implement Athena query execution
  // For MVP, mock return
  return [];
}
```

---

## 7. Frontend Dashboard (Next.js)

### pages/datasets/[id].tsx
```typescript
import React, { useState } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend } from 'recharts';

export default function DatasetPage({ params: { id } }: any) {
  const [from, setFrom] = useState(new Date(Date.now() - 90 * 24 * 60 * 60 * 1000));
  const [to, setTo] = useState(new Date());
  const [data, setData] = useState<any[]>([]);

  React.useEffect(() => {
    fetch(`/api/v1/datasets/${id}/data?from=${from.toISOString().split('T')[0]}&to=${to.toISOString().split('T')[0]}`)
      .then(r => r.json())
      .then(d => setData(d.data));
  }, [id, from, to]);

  return (
    <div className="p-8 max-w-6xl mx-auto">
      <h1 className="text-3xl font-bold mb-4">
        {id === 'inflation' ? 'IPCA Inflação' : id}
      </h1>

      <div className="flex gap-4 mb-6">
        <input
          type="date"
          value={from.toISOString().split('T')[0]}
          onChange={(e) => setFrom(new Date(e.target.value))}
        />
        <input
          type="date"
          value={to.toISOString().split('T')[0]}
          onChange={(e) => setTo(new Date(e.target.value))}
        />
      </div>

      <LineChart width={800} height={400} data={data}>
        <CartesianGrid strokeDasharray="3 3" />
        <XAxis dataKey="month" />
        <YAxis />
        <Tooltip />
        <Legend />
        <Line type="monotone" dataKey="rate_12m_pct" stroke="#8884d8" />
      </LineChart>

      <div className="mt-8">
        <h2 className="text-xl font-bold mb-4">Estatísticas</h2>
        {/* Stats cards */}
      </div>
    </div>
  );
}
```

---

## 8. Deployment via GitHub Actions

### .github/workflows/deploy.yml
```yaml
name: Deploy CDK

on:
  push:
    branches: [main]
    paths:
      - 'infra/**'
      - 'lambda/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '20'
      
      - name: Install CDK
        run: npm install -g aws-cdk
      
      - name: Install dependencies
        run: cd infra && npm install
      
      - name: Lint & Type Check
        run: npx tsc --noEmit
      
      - name: Deploy CDK
        run: cdk deploy --require-approval never
        env:
          AWS_REGION: us-east-1
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

---

## 9. Cost Estimate (Monthly)

| Service | Usage | Cost |
|---------|-------|------|
| S3 Storage (100 GB) | 100 GB × $0.023/GB | $2.30 |
| Athena Queries | 1000 queries × $5/TB × 10GB avg | $50 |
| Lambda Ingest (4 functions × 5 min/day) | 600 min/mo × $0.20/1M ms | $0.12 |
| API Gateway (10k requests/day) | 300k req/mo × $0.0035 | $1.05 |
| **Total** | | **~$54/mês** |

💡 **Savings vs Economatica:** R$ 54/mês vs R$ 5.000+/mês = 100× cheaper

---

## 10. Post-MVP Roadmap (Passo 3+)

- [ ] **Solana Integration** — smart contract for license validation
- [ ] **User Management** — tier system (Free, Pro, Enterprise)
- [ ] **Advanced Analytics** — ML forecasting, anomaly detection
- [ ] **Real-time Alerts** — WebSocket + email/SMS notifications
- [ ] **Data Marketplace** — custom dataset subscriptions

---

**Próxima fase:** Implementação de Passo 2 com aprovação do time.

