# Brainstorm: Passo 2 — MVP de Dados (Sem Blockchain Ainda)

**Data:** 21 Set 2026  
**Facilitadores:** @analyst, @architect  
**Objetivo:** Definir o escopo do MVP de dados consolidados (Data Warehouse + API) antes de qualquer integração Solana  
**Output esperado:** Identificar datasets iniciais, arquitetura de ingestão, e exposição via API

---

## 1. Contexto Estratégico

### O Problema
Empresas brasileiras (PMEs, consultores, traders de commodities) precisam de dados microeconômicos consolidados:
- **IBGE** – indicadores econômicos, inflação, desemprego
- **ANP** – preços de combustível, produção de petróleo
- **RAIS** – dados de mercado laboral, salários por setor
- **Atualmente:** cada um extrai esses dados manualmente de portais públicos ou paga por APIs caras (Bloomberg, Refinitiv, Economatica)

### A Oportunidade
**Marketplace de dados como Economatica**, mas:
- Focado em dados públicos consolidados
- Preço acessível (SaaS recorrente vs. caríssimo Economatica)
- Fácil integração (REST API, dashboards prontos, gráficos)
- Blockchain (Solana) como layer de monetização e rastreabilidade

### MVP Scope (Passo 2)
**Dados armazenados fora da chain.** Apenas prototipo REST API + frontend com 3-5 datasets consolidados. Zero blockchain neste passo.

---

## 2. Datasets Candidatos (Top 5 para MVP)

### Dataset A: Inflação Acumulada (IBGE IPCA)
- **Fonte:** IBGE API pública (https://servicodados.ibge.gov.br/)
- **Frequência:** Mensal
- **Variáveis:** taxa acumulada 12 meses, índices por categoria (alimentos, combustível, vestuário, etc.)
- **Tamanho:** ~200 KB/mês (negligenciável)
- **Caso de uso:** Dashboard de inflação, alertas de picos, comparativo com cesta de bens
- **Dificuldade:** ⭐ Baixa (API simples, dados públicos, sem autenticação)

**Consolidação:**
```sql
CREATE TABLE inflation_ipca (
  id INT PRIMARY KEY,
  month DATE NOT NULL,
  rate_12m_pct DECIMAL(10, 2),
  rate_month_pct DECIMAL(10, 2),
  food_pct DECIMAL(10, 2),
  fuel_pct DECIMAL(10, 2),
  created_at TIMESTAMP DEFAULT NOW()
);
```

### Dataset B: Preços de Combustível Médios (ANP)
- **Fonte:** ANP API ou web scrape (https://dados.gov.br/dados/datasets/)
- **Frequência:** Semanal
- **Variáveis:** gasolina comum, gasolina aditivada, diesel, etanol (por estado, por distribuidor)
- **Tamanho:** ~5-10 MB acumulado (1000 registros/semana)
- **Caso de uso:** Análise de tendências de combustível, impacto em custos logísticos, simulador de preços
- **Dificuldade:** ⭐⭐ Média (web scrape ou parser XML, histórico necessário)

**Consolidação:**
```sql
CREATE TABLE fuel_prices_anp (
  id INT PRIMARY KEY,
  week_date DATE NOT NULL,
  state VARCHAR(2),
  distributor_id INT,
  fuel_type VARCHAR(20), -- gasolina_comum, diesel, etanol
  avg_price_brl DECIMAL(10, 2),
  price_change_pct DECIMAL(10, 2),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (week_date, state, fuel_type)
);
```

### Dataset C: Desemprego e Mercado de Trabalho (RAIS/CAGED)
- **Fonte:** IBGE PNAD, MTE CAGED API, ou dados.gov.br
- **Frequência:** Mensal/Trimestral
- **Variáveis:** taxa de desemprego, admissões, demissões, por setor econômico
- **Tamanho:** ~1-2 MB (histórico 5 anos)
- **Caso de uso:** Previsão de tendências de contratação, insights RH, análise de rotatividade
- **Dificuldade:** ⭐⭐⭐ Alta (múltiplas fontes, dados complexos, RAIS requer LGD de acesso)

**Consolidação:**
```sql
CREATE TABLE labor_market_caged (
  id INT PRIMARY KEY,
  month DATE NOT NULL,
  sector_code VARCHAR(10),
  sector_name VARCHAR(100),
  hires INT,
  layoffs INT,
  net_job_change INT,
  unemployment_rate_pct DECIMAL(10, 2),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (month, sector_code)
);
```

### Dataset D: PIB por Setor (IBGE)
- **Fonte:** IBGE Contas Nacionais Trimestrais
- **Frequência:** Trimestral
- **Variáveis:** PIB total, crescimento trimestral, PIB por setor (agropecuária, indústria, serviços)
- **Tamanho:** ~500 KB (histórico 20 anos)
- **Caso de uso:** Análise macroeconômica, cenários de investimento, trends setoriais
- **Dificuldade:** ⭐⭐ Média (dados bem estruturados, mas atualização trimestral)

**Consolidação:**
```sql
CREATE TABLE gdp_by_sector (
  id INT PRIMARY KEY,
  quarter DATE NOT NULL, -- YYYY-Q1/Q2/Q3/Q4
  sector VARCHAR(50), -- total, agropecuaria, industria, servicos
  gdp_brl_billions DECIMAL(15, 2),
  gdp_growth_pct DECIMAL(10, 2), -- vs ano anterior
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (quarter, sector)
);
```

### Dataset E: Commodities de Exportação (Preços Internacionais)
- **Fonte:** World Bank Commodities Price API, ou IPEADATA
- **Frequência:** Diária/Semanal
- **Variáveis:** preço de café, açúcar, minério de ferro, ouro, brent oil
- **Tamanho:** ~2-3 MB
- **Caso de uso:** Simulador de receita de exportações, alertas de picos de preço, análise de risco cambial
- **Dificuldade:** ⭐⭐ Média (API externa estável, mas dados em USD)

**Consolidação:**
```sql
CREATE TABLE commodity_prices (
  id INT PRIMARY KEY,
  date DATE NOT NULL,
  commodity_code VARCHAR(20), -- COFFEE, SUGAR, IRON_ORE, GOLD, BRENT_OIL
  commodity_name VARCHAR(100),
  price_usd DECIMAL(15, 4),
  price_brl DECIMAL(15, 4), -- conversão diária USD/BRL
  change_24h_pct DECIMAL(10, 2),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (date, commodity_code)
);
```

---

## 3. Arquitetura de Ingestão (Data Warehouse)

### Opção A: AWS (CDK + S3 + Athena) — Recomendado para Cesar
**Stack:** AWS S3 (data lake) + Athena (querying) + Lambda (ingestão) + EventBridge (scheduler)

**Vantagens:**
- ✅ Cesar já domina CDK
- ✅ Custo baixo (S3: $0.025/GB/mês, Athena: $5 por TB scaneado)
- ✅ Scalável (S3 sem limite)
- ✅ Fácil integração com Solana (RPC via Lambda)

**Fluxo:**
```
EventBridge (cron) 
  → Lambda (ingestão)
  → Parse IBGE/ANP/RAIS JSON
  → Enriquecimento (conversão BRL/USD, normalizações)
  → S3 (Parquet particionado por data)
  → Athena SQL queries
  → Lambda (REST API)
  → Cliente
```

**Exemplo Lambda (Node.js):**
```typescript
// lambda/ingest-inflation.ts
import AWS from 'aws-sdk';
const s3 = new AWS.S3();

export async function handler() {
  const response = await fetch('https://servicodados.ibge.gov.br/api/v3/...');
  const data = await response.json();
  
  const parquet = convertToParquet(data);
  await s3.putObject({
    Bucket: 'colosseum-data-lake',
    Key: `inflation/month=${new Date().toISOString().split('T')[0]}/data.parquet`,
    Body: parquet
  }).promise();
  
  return { statusCode: 200, body: 'Inflação ingerida com sucesso' };
}
```

### Opção B: BigQuery (Google) — Alternativa escalável
**Stack:** Google BigQuery + Cloud Functions + Cloud Scheduler

**Vantagens:**
- ✅ Melhor para analytics (SQL complexo, ML integrado)
- ✅ Custo previsível (slot billing)
- ✅ Datasets públicos IBGE já existem no BigQuery

**Desvantagem:**
- ❌ Cesar não trabalha com GCP tão fluentemente
- ❌ Custo mínimo: $100/mês (slot pricing)

### Opção C: Postgres local + Cronjob — MVP rápido
**Stack:** PostgreSQL local + Python cron scripts + REST API Flask/FastAPI

**Vantagens:**
- ✅ MVP em 1-2 dias
- ✅ Zero custo (rode em servidor existente)
- ✅ Fácil de debugar

**Desvantagem:**
- ❌ Não escala para milhões de registros
- ❌ Precisa de backup manual
- ❌ Não ideal para produção

---

## 4. Exposição via API REST

### Endpoints Sugeridos (MVP)

```
GET /api/v1/datasets
  → Lista datasets disponíveis

GET /api/v1/datasets/{id}/data
  ?from=2024-01-01&to=2024-12-31
  → Retorna série temporal JSON

GET /api/v1/datasets/{id}/chart
  ?type=line&period=daily
  → SVG/PNG pré-renderizado (Plotly)

GET /api/v1/datasets/{id}/stats
  → Estatísticas (min, max, média, std dev)

POST /api/v1/datasets/{id}/alert
  ?threshold=10&operator=gt
  → Cria alerta (email quando inflação > 10%)
```

### Exemplo Response

```json
{
  "dataset_id": "inflation_ipca",
  "data": [
    {
      "month": "2024-01-01",
      "rate_12m_pct": 4.52,
      "rate_month_pct": 0.65,
      "category_breakdown": {
        "food": 8.3,
        "fuel": 2.1,
        "clothing": 1.2
      }
    }
  ],
  "metadata": {
    "last_updated": "2024-12-31",
    "next_update": "2025-01-15",
    "data_source": "IBGE"
  }
}
```

### Autenticação (Preparação para Solana)
**MVP:** JWT simples (sem blockchain).
**Produçção (Passo 3):** JWT validado contra contrato Solana (scopes: `read:inflation`, `read:fuel_prices`, etc.)

```typescript
// middleware/auth.ts
export async function validateJWT(token: string): Promise<Scope[]> {
  const decoded = jwt.verify(token, process.env.JWT_SECRET);
  return decoded.scopes; // ex: ['read:inflation', 'read:commodity_prices']
}
```

---

## 5. Frontend (Dashboards Prontos)

### Tech Stack
- **Framework:** React 18 + Next.js
- **Charts:** Recharts ou Plotly.js
- **UI Components:** Shadcn/ui
- **Hosting:** Vercel ou Lovable

### Mockups de Páginas Essenciais

#### Page 1: Dashboard Home
- Cartão de Inflação (IPCA últimos 12 meses)
- Gráfico de Preços de Combustível (últimos 3 meses)
- Tabela de Desemprego por Setor
- Miniaturar: PIB trimestral, Commodities

#### Page 2: Dataset Detail
- Série temporal com zoom/pan
- Estatísticas (min, max, avg)
- Comparação com período anterior
- Download em CSV/JSON
- Filtros por período, setor, estado

#### Page 3: Alertas
- Configurar thresholds (e.g., "avisa se gasolina > R$ 7.00")
- Email notification mockup

#### Page 4: Pricing
- 3 tiers (Free, Pro, Enterprise)
- Indicar que "Passo 3 integra pagamento Solana"

---

## 6. Cronograma de Ingestão

### Semanal (ANP Combustíveis)
```cron
0 2 * * 1 # Segunda-feira 02h UTC
λ ingest-fuel-prices
```

### Mensal (IBGE IPCA)
```cron
0 10 15 * * # Dia 15 de cada mês 10h UTC
λ ingest-inflation-ipca
```

### Trimestral (PIB)
```cron
0 10 15 1,4,7,10 * # 15 de jan/abr/jul/out
λ ingest-gdp
```

### Sob Demanda (Commodities — World Bank API)
```cron
0 */4 * * * # A cada 4 horas
λ ingest-commodity-prices
```

---

## 7. Critérios de Qualidade MVP

| Aspecto | Critério | MVP? |
|---------|----------|------|
| **Datasets** | 3-5 consolidados | ✅ Sim (IPCA, ANP, RAIS básico) |
| **Dados históricos** | 3+ anos | ✅ Sim (suficiente para tendências) |
| **Atualização** | Automática via cron | ✅ Sim |
| **API REST** | 5+ endpoints | ✅ Sim |
| **Dashboard** | 4-5 páginas core | ✅ Sim |
| **Autenticação** | JWT (preparação para Solana) | ✅ Sim |
| **Test coverage** | ≥ 70% | ⚠️ Esforço (adiar se timeline apertada) |
| **Blockchain** | ❌ Não | ✅ Deixar para Passo 3 |

---

## 8. Dependências e Riscos

### Dependências Técnicas
- [ ] Acesso APIs IBGE, ANP, RAIS (todas públicas — sem bloqueio esperado)
- [ ] AWS account + CDK setup (Cesar já tem)
- [ ] Conhecimento de Parquet/Athena (baixo — documentado)

### Dependências Regulatórias
- [x] **CRÍTICO:** Validar termos de redistribuição de dados IBGE/ANP/RAIS
  - IBGE: Dados públicos, permitida comercialização
  - ANP: Dados públicos, mas verificar T&Cs específicos
  - RAIS: Dados anonimizados, sem restrição, MAS alguns campos sensíveis podem precisar mascaramento
- **Ação:** Antes de Passo 2, enviar email para contatos legais dessas entidades

### Riscos de Projeto

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---|---|---|
| ANP bloqueia scrape | Média | Alto | Usar dados.gov.br ou API alternativa |
| API IBGE lenta (rate limit) | Baixa | Médio | Cache local 24h + retry exponencial |
| Dados inconsistentes entre fontes | Alta | Médio | Normalização em SQL, testes de validação |
| Mudanças de schema (IBGE adiciona campos) | Baixa | Médio | Versionamento de schema, monitoramento |

---

## 9. Próximos Passos (Ações)

### Imediato (Esta semana)
- [ ] **@analyst** → Validar com contatos IBGE/ANP/RAIS (email/LinkedIn)
- [ ] **@architect** → Prototipar Lambda de ingestão (IPCA — mais simples)
- [ ] **@pm** → Draft PRD com esses 5 datasets
- [ ] **@dev** → Setup AWS CDK base + S3 bucket

### Próxima semana
- [ ] Ingestão funcional para 3 datasets (IPCA, ANP, Commodities)
- [ ] API REST basic (Lambdas + API Gateway)
- [ ] Dashboard Next.js com 3 gráficos

### Fim da semana 2
- [ ] 5 datasets consolidados + testes
- [ ] Frontend 80% pronto
- [ ] Pronto para Passo 3 (Solana integração)

---

## 10. Benchmarks Conhecidos

### Economatica
- **Preço:** ~R$ 5k-20k/mês (empresas grandes)
- **Datasets:** 200+ indicadores brasileiros
- **API:** Sim, mas restrita
- **Diferencial nosso:** Preço 10× menor, focado em públicos, fácil integração

### Bloomberg Terminal
- **Preço:** ~$20k-30k/mês (instituições)
- **Datasets:** Globais
- **Diferencial nosso:** Especializado em dados BR, acessível a PMEs

### Alternativas Abertas
- **IPEADATA:** API simples, mas UI desatualizada
- **dados.gov.br:** Repositório bruto, sem consolidação
- **Alpha Vantage:** Apenas commodities/forex, não macro BR

---

## 11. Conclusão

**MVP de Dados (Passo 2) é viável em 2 semanas com o stack recomendado (AWS CDK).**

**Valor entregue:**
1. ✅ Data warehouse consolidado de 5 datasets públicos
2. ✅ API REST pronta para consumo
3. ✅ Dashboards que mostram tendências econômicas
4. ✅ Autenticação JWT preparada para Solana (Passo 3)
5. ✅ Cronogramas de ingestão automática

**Sem Solana ainda — apenas dados. Blockchain entra quando temos tração (Passo 3).**

---

**Próxima reunião:** Hoje (21 set) — Call do time para aprovação deste brainstorm e definição de prioridades de datasets.

