# Perfil do Time, Ideias & Especialidades

**Projeto:** Hackathon Colosseum 2026
**Data:** 22 Set 2026
**Status:** 📋 Em construção — ideias em aberto / brainstorm ativo

---

## 1. Visão Geral do Time

Time enxuto com complementaridade forte entre **domínio (economia/dados)** e **tecnologia (cloud/engenharia)**. A tese central do produto nasce da vivência prática de consumo de dados públicos no dia a dia — não de uma suposição de mercado.

| Membro | Papel | Especialidade Central | Status |
|--------|-------|-----------------------|--------|
| Marcelo Martins | Domain Expert / Cientista de Dados | Economia aplicada, dados públicos, consultoria | ✅ Perfil completo |
| Cesar Schneider | Tech Lead / Arquiteto | AWS/CDK, cloud, DevOps, IA/LLM | ✅ Perfil (a confirmar) |
| *(a preencher)* | — | — | ⏳ Aguardando |

---

## 2. Perfil dos Membros

### 👤 Marcelo Martins — Economista / Cientista de Dados

**Formação & Background**
- Economista, cursando **doutorado em Economia Aplicada**
- Atua também como **cientista de dados** (autodidata / "se arrisca")
- **Consultor** para empresas em múltiplos segmentos e temáticas:
  - Tributação
  - Comércio Exterior (comex)
  - Energia
  - Outros setores

**Vivência de Campo (origem da ideia)**
- Consome **informações públicas diariamente** de diversas fontes de dados
- Desenvolve **soluções bem específicas para cada cliente** (ETL sob demanda)
- Dor real: precisa montar o ETL de uma base específica e depois repetir para outra — não existe solução que já entregue isso pronto

**Especialidades**
- Economia aplicada (micro e macro)
- Análise de dados econômicos e setoriais
- ETL e processamento de bases públicas (IBGE, ANP, RAIS, etc.)
- Consultoria estratégica para empresas (tributário, comex, energia)

**Visão de Produto (tese central)**
> Não existe plataforma que agregue informações a **nível municipal e de indivíduo (micro)**, de fácil acesso. As soluções no mercado focam apenas em variáveis **macro** (PIB, inflação, atividade econômica, indicadores agregados).

**Exemplos do que falta no mercado**
- Consumo de **combustível em um município** específico
- **Remuneração média** de uma determinada atividade econômica
- Dados micro acessíveis sem ETL manual

**Sugestão de direção técnica**
- Para o protótipo, não precisa nada robusto ainda
- Mas pensar em **processamento e armazenamento de big data** desde cedo é um diferencial competitivo importante

---

### 👤 Cesar Schneider — Tech Lead / Arquiteto

**Formação & Background**
- Fundador / parceiro eWorks Labs
- Especialista em infraestrutura cloud e arquitetura de software

**Especialidades**
- **AWS** (CDK, serverless: Lambda, API Gateway, S3, Athena)
- **DevOps** e CI/CD (GitHub Actions)
- **Arquitetura de software** (multi-tenant, serverless)
- **IA/LLM** (Bedrock, LiteLLM, agentes)

**Contribuição ao Projeto**
- Liderança técnica e decisão de stack
- Infraestrutura como código (CDK)
- Integração Solana (Passo 3)

*(Perfil a confirmar/detalhar com o próprio Cesar)*

---

## 3. Ideias em Aberto (Brainstorm)

**Estado:** Ideias ainda em aberto — não há produto fechado ainda. A tese mais forte até agora vem da dor do Marcelo.

### 💡 Tese Principal — "Marketplace de Dados Públicos Micro (BR)"

**Problema:** Empresas, consultores e analistas precisam de dados microeconômicos públicos (municipal/individual), mas:
- Cada um faz o próprio ETL manual de cada base
- Soluções existentes só cobrem **macro** (Economatica, Bloomberg, IPEADATA)
- Não existe agregação de nível **micro** com acesso fácil

**Oportunidade:** Plataforma que consolida bases públicas micro e expõe via API + dashboard, a custo acessível.

**Diferenciais competitivos**
- Foco em dados **micro** (municipal/individual) — nicho não atendido
- Preço 10-100× menor que concorrentes (Economatica/Bloomberg)
- ETL pronto (sem trabalho manual para o cliente)
- Blockchain (Solana) como layer de monetização/rastreabilidade (Passo 3)

### 🧩 Variações / Ângulos a explorar
- **Ângulo micro-first:** consumo de combustível por município, remuneração por atividade (tese do Marcelo)
- **Ângulo macro-first:** IPCA, ANP, commodities (brainstorm anterior — Passo 2)
- **Ângulo híbrido:** começar macro (mais simples) e evoluir para micro (diferencial real)

### 🔀 Decisão em aberto
- Qual ângulo priorizar no MVP: **macro simples** vs. **micro diferencial**?
- Quão "big data" precisa ser o protótipo (armazenamento/processamento)?

---

## 4. Mapeamento de Skills → Produto

| Necessidade do Produto | Quem Cobre | Gaps |
|------------------------|-----------|------|
| Domínio econômico / validação de dados | Marcelo | — |
| ETL de bases públicas | Marcelo | Automatização (Cesar) |
| Arquitetura cloud / CDK | Cesar | — |
| Processamento big data | ⚠️ A definir | Possível gap (Spark/Athena/Redshift?) |
| Frontend / UX | ⚠️ A definir | **GAP** |
| Solana / blockchain | ⚠️ A definir | **GAP** (Passo 3) |
| Marketing / GTM / tração | ⚠️ A definir | **GAP** |

---

## 5. Próximos Passos

- [ ] Confirmar/expandir perfil do Cesar
- [ ] Listar demais membros (se houver)
- [ ] Fechar ângulo do MVP (macro vs micro)
- [ ] Definir quem cobre os gaps (frontend, Solana, GTM)

---

**Última atualização:** 22 set 2026
