# RESUMO EXECUTIVO — Call de hoje (21 Set)

## 📊 Brainstorm PASSO 2: MVP de Dados (Sem Blockchain)

**Status:** ✅ **Documentação completa no GitHub** — pronta para discussão

---

## 🎯 Decisões Críticas para Decidir HOJE

### 1. Datasets Iniciais (Escolher 3 de 5)
| Dataset | Prioridade | Dificuldade | Valor |
|---------|-----------|-----------|-------|
| **IPCA (Inflação)** | 🔴 P0 | ⭐ Fácil | Alto (diário para clientes) |
| **ANP (Combustível)** | 🔴 P0 | ⭐⭐ Média | Alto (logística, transportes) |
| **Commodities** | 🟡 P1 | ⭐⭐ Média | Alto (exportadores) |
| **PIB Setorial** | 🟡 P1 | ⭐⭐ Média | Médio (análise macro) |
| **RAIS (Mercado Trabalho)** | 🟡 P1 | ⭐⭐⭐ Alta | Médio (RH/análise) |

**Recomendação:** Começar com **IPCA + ANP + Commodities** (3 datasets fáceis em paralelo)

---

### 2. Stack Técnico (AWS CDK Aprovado)

```
Ingestão:      Lambda + EventBridge (cron)
Data Lake:     S3 + Parquet (particionado)
Querying:      Athena (SQL direto em S3)
API:           API Gateway + Lambda (REST)
Frontend:      Next.js + Recharts
Auth:          JWT simples (prep para Solana)
Custo:         ~R$ 54/mês
```

✅ **Vantagem:** Cesar domina CDK; sem operational overhead.

---

### 3. Timeline Proposta

```
HOJE (21 set)      → Aprovação de datasets + stack
Segunda (22 set)   → Lambda de ingestão IPCA funcional
Terça (23 set)     → API REST + Dashboard com 3 gráficos
Quarta (24 set)    → 5 datasets consolidados + testes
Quinta (25 set)    → Pronto para Passo 3 (Solana)
```

**Viável?** Sim, se foco total em dados (sem blockchain ainda).

---

## 📋 Documentação Criada

### Arquivo 1: `PASSO-2-MVP-DADOS-BRAINSTORM.md`
- 5 datasets com schemas SQL
- Comparação Opção A (AWS) vs B (BigQuery) vs C (Postgres local)
- API endpoints especificados
- Frontend mockups
- Cronograma de ingestão
- Riscos identificados

### Arquivo 2: `PASSO-2-ARQUITETURA-TECNICA.md`
- Diagrama ASCII completo
- CDK TypeScript (data-lake-stack, ingest-stack, api-stack)
- Lambda de ingestão com Parquet
- Athena DDL (SQL schemas)
- API endpoints (GET /data, POST /alert)
- Next.js dashboard exemplo
- GitHub Actions CI/CD
- Cost estimate

---

## 💰 ROI vs Competidores

| Plataforma | Preço/mês | Datasets | Acesso |
|-----------|-----------|----------|--------|
| **Economatica** | R$ 5.000+ | 200+ | Lento (portal) |
| **Bloomberg Terminal** | R$ 30.000+ | Globais | Caro |
| **Nosso MVP** | R$ 54 | 5-10 | API + Dashboard |

**100× mais barato que Economatica. Valor.**

---

## ⚠️ Dependências Legais (CRÍTICAS)

**Ação imediata:** Validar termos de redistribuição com:
- [ ] IBGE — dados públicos, redistribuição permitida?
- [ ] ANP — dados públicos, mas verificar T&Cs específicos
- [ ] RAIS — dados anonimizados, sem restrição

**Prazo:** Antes de Passo 2 começar (segunda-feira).

---

## 🚀 Próximos Passos Após Aprovação

1. **@architect** → Setup CDK + S3 bucket
2. **@dev** → Lambda de ingestão IPCA (cópia/cola do brainstorm)
3. **@dev** → API GET /data (Athena queries)
4. **@dev** → Dashboard Next.js (Recharts)
5. **@qa** → Testes + validação de dados
6. **@devops** → CI/CD + deploy automático

---

## 🎤 Perguntas para Call

1. **Datasets aprovados?** (IPCA, ANP, Commodities ou outros?)
2. **Stack AWS confirmado?** (ou preferem alternativa?)
3. **Timing:** Começar segunda (22 set)?
4. **Quem valida licenças com IBGE/ANP/RAIS?**

---

**Documentação:** https://github.com/cesschneider/colosseum-hackathon/tree/master/docs/brainstorming

**Status Git:** ✅ Committed e pushed

