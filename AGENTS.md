# Hackathon Colosseum 2026 — Agentes & Diretrizes de Desenvolvimento

## 📋 Visão Geral do Projeto

**Nome:** Hackathon Colosseum 2026  
**Objetivo:** Participar e vencer o Hackathon Colosseum (14 set – 12 out 2026)  
**Foco:** Desenvolvimento de produto blockchain/crypto com integração Solana  
**Modelo de Desenvolvimento:** AIOX-Core + G-Stack (Spec-Driven)  
**Status:** Fase de Documentação e Pesquisa (em andamento)

---

## 🤖 Roster de Agentes AIOX-Core

Todas as implementações seguem o framework **AIOX-Core** com seus 12 agentes especializados e 6 leis constitucionais.

| Agent | Role | Responsabilidades |
|-------|------|-------------------|
| `@aiox-master` | Master Orchestrator | Coordena todo o fluxo; validação de conformidade |
| `@analyst` | Business Analyst | Pesquisa, brainstorming, análise de mercado |
| `@architect` | Tech Architect | Design de stack, API design, data model |
| `@data-engineer` | Data Engineer | Design de BD, migrations, índices |
| `@dev` | Full Stack Developer | **Implementação de código (obrigatório AIOX framework)** |
| `@devops` | GitHub/CI Manager | ÚNICO agente que pode `git push` |
| `@pm` | Product Manager | PRD creation, visão do produto |
| `@po` | Product Owner | Validação de histórias, backlog |
| `@qa` | QA Architect | Testes, quality gates |
| `@sm` | Scrum Master | Criação de histórias, gestão de branches |
| `@ux-design-expert` | UX Design | Design, acessibilidade, UI |
| `@squad-creator` | Custom Squads | Criação de squads especializados |

---

## ⚖️ As 6 Leis Constitucionais (INVIOLÁVEIS)

1. **CLI First** — toda feature funciona 100% via CLI antes de qualquer UI
2. **Agent Authority** — `@devops` é o ÚNICO que pode `git push` ou criar PRs
3. **Story-Driven** — zero código sem arquivo de story associado (HARD BLOCK)
4. **No Invention** — toda linha de spec deve rastrear a um requisito (FR-*, NFR-*, CON-*)
5. **Quality First** — `npm run lint` + `npm run typecheck` + `npm test` devem passar antes de push
6. **Absolute Imports** — APENAS caminhos `@/`, nunca `../../../`

---

## 💻 Diretrizes de Implementação de Código

### ✅ AIOX Framework - OBRIGATÓRIO

**TODOS os código-fonte devem usar o AIOX-Core framework:**

- Instalação: `npx @aiox-squads/core install --ci --yes --ide claude-code`
- Estrutura de pastas: `/docs/stories/`, `/docs/prd/`, `/docs/architecture/`
- Story files: `docs/stories/epic-N/STORY-N.M-slug.md` com status (Draft → Approved → InProgress → Review → Done)
- Qualidade: lint + typecheck + testes devem passar ANTES de qualquer commit
- Controle de versão: Git com proteção de branches (só `@devops` faz push)

**Por quê?** AIOX garante traceabilidade completa, governança story-driven, e qualidade consistente — essencial para um hackathon competitivo.

---

## 📊 Fase Atual: Documentação e Pesquisa (G-Stack)

Estamos na **Fase 1 de Documentação e Pesquisa** usando **G-Stack Spec-Driven Development**.

### Fluxo G-Stack (5 Fases)

```
Phase 1: Entender o "Por Quê"
   ↓
Phase 2: Escopo e Limites
   ↓
Phase 3: Interrogação Técnica
   ↓
Phase 4: Revisão de Rascunho
   ↓
Phase 4.5-5: Quality Gate + Arquivo
```

---

## 📚 Recursos Requeridos de Documentação

### Arquivos a Gerar (por ordem de prioridade)

1. **`docs/brainstorming/analyst-output.md`** (@analyst)
   - Visão do produto + declaração de problema
   - Usuários-alvo + ICP
   - Requisitos funcionais (FR-*) e não-funcionais (NFR-*)
   - Riscos + mitigações
   - Landscape competitivo
   - Métricas de sucesso

2. **`docs/prd/epic-0-hackathon-mvp.md`** (@pm)
   - 20+ requisitos funcionais (FR-001+)
   - 10+ requisitos não-funcionais (NFR-001+)
   - 5+ constraints (CON-001+)
   - User stories com acceptance criteria
   - Out-of-scope explícito
   - Roadmap (MVP vs Phase 2/3)

3. **`docs/architecture/`** (@architect)
   - `tech-stack.md` — tecnologia + rationale
   - `system-design.md` — diagrama ASCII, componentes
   - `data-model.md` — tabelas, fields, SQL
   - `api-design.md` — CLI tree, config, formatos

4. **`docs/stories/epic-0/STORY-*.md`** (@sm)
   - Status: Draft → Approved → InProgress → Review → Done
   - Acceptance criteria
   - Notas técnicas
   - Dependências (DEP-*)

---

## 🔍 Avaliação do Colosseum (Critérios dos Jurados)

| Dimensão | O que procuram |
|----------|---|
| **Produto** | MVP funcional, UX clara, feature-complete |
| **Tração** | Usuários reais, transações blockchain, TVL, volume |
| **Distribuição** | Go-to-market realista, adoção, crescimento |

---

## 📅 Timeline (CRÍTICA)

```
Hoje (21 set)        → Pesquisa + Spec (G-Stack)
14 set – 12 out      → Build + Mentorias (AIOX-Core)
12 out 23h59 PT      → Deadline FINAL
= -21 dias           → URGENTE
```

**Importante:** Código ANTES de 14 set NÃO conta. Após 14 set, apenas código novo conta.

---

## 🎯 Próximos Passos (Para Agentes)

### Fase Imediata (Pesquisa)

1. **@analyst** → `docs/brainstorming/analyst-output.md`
   - Brainstorm de nicho (DeFi? Payments? AI?)
   - Análise de competidores no Colosseum
   - Visão do MVP

2. **@architect** → Pesquisa tech stack
   - Blockchain? (Solana recomendado)
   - Linguagem? (Rust, Solidity, TypeScript?)
   - Framework? (Anchor, near-cli, ethers.js?)

3. **@pm** → Draft PRD (`docs/prd/epic-0-hackathon-mvp.md`)
   - Features core (FR-001+)
   - Constraints (CON-001+)
   - User stories

4. **@sm** → Design de histórias
   - Quebra PRD em histórias (STORY-0.1, STORY-0.2, etc.)
   - Cada história = 1-2 dias de trabalho

### Após Aprovação de Spec (14 set +)

5. **@dev** → Implementa usando AIOX
   - Lê histórias aprovadas
   - Cria branches via `@sm`
   - Commits com `Closes #STORY-N.M`

6. **@devops** → Gerencia GitHub
   - Revisa PRs
   - ÚNICO que `git push`
   - Cria/merge PRs

7. **@qa** → Valida qualidade
   - Unit + integração tests
   - Coverage ≥ 80%
   - E2E críticos

---

## 🔗 Referências Principais

- **Wiki Superteam Brasil:** https://wiki.superteam.com.br
- **Landing:** https://hackathon.superteam.com.br
- **Plataforma:** https://colosseum.com
- **AIOX-Core:** https://github.com/SynkraAI/aiox-core
- **Eworks OS (case study):** https://github.com/eworks-cloud/eworks-os

---

**Última atualização:** 21 set 2026  
**Status:** 📋 Documentação e Pesquisa ativa (G-Stack Phase 1-2)  
**Próximo:** Spec completo (Phase 4 aprovado)
