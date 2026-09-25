# SNIS / SINISA — saneamento por município (água, esgoto e qualidade)

## Fonte

- **Órgão:** Ministério das Cidades / Secretaria Nacional de Saneamento.
- **Duas origens, unidas nos códigos históricos do SNIS:**
  1. **SNIS – Série Histórica (2000 a 2022):** aplicação <https://app4.cidades.gov.br/serieHistorica/> (antigo `app4.mdr.gov.br`). Não há download em massa oficial: a exportação é feita na aplicação (relatório *Consolidado por Município*) e os arquivos gerados são colocados manualmente em `dados/brutos/snis_sinisa/serie_historica/` (passo a passo abaixo).
  2. **SINISA (ano de referência 2023 em diante):** pacotes ZIP oficiais descobertos nas páginas <https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/resultados-sinisa> e <https://www.gov.br/cidades/pt-br/acesso-a-informacao/acoes-e-programas/saneamento/sinisa/planilhas-de-informacoes-e-indicadores>. Em 2023: `SINISA_Resultados_Ref2023.zip` (água, 19,8 MB) e `SINISA_ESGOTO_Planilhas_2023_v2.zip` (esgoto, 10,2 MB). Anos novos com o mesmo padrão de nome (`SINISA_*Resultados_Ref<ano>.zip`, `SINISA_*Planilhas_<ano>*.zip`) entram automaticamente; as URLs de 2023 ficam como reserva.

## Arquivos

| Script | Papel |
|---|---|
| `01_extracao_snis_sinisa.R` | baixa os ZIPs do SINISA para `dados/brutos/snis_sinisa/sinisa/`, extrai apenas as planilhas *Informações de Gestão Técnica – Base Municipal* (água e esgoto) para `sinisa/<ano>/` e confere se há exportações da Série Histórica em `serie_historica/` |
| `02_tratamento_snis_sinisa.R` | lê as duas origens, converte códigos (6 → 7 dígitos), une, calcula os indicadores derivados e grava `dados/tratados/snis_sinisa/snis_sinisa_municipal.csv` + `snis_sinisa_dicionario_variaveis.csv` |

## Indicadores (`snis_sinisa_municipal.csv`, uma linha por município-ano)

| variável | código SNIS | descrição | unidade | equivalente SINISA (2023+) |
|---|---|---|---|---|
| `populacao_urbana_residente_agua` | G06A | população urbana residente dos municípios atendidos com água | habitantes | DFE0002 |
| `populacao_total_residente_agua` | G12A | população total residente dos municípios atendidos com água | habitantes | DFE0001 |
| `populacao_total_atendida_agua` | AG001 | população total atendida com abastecimento de água | habitantes | GTA0001 + GTA0002 (urbana + rural) |
| `economias_ativas_agua` | AG003 | economias ativas de água | economias | GTA0008 + GTA0015 |
| `volume_agua_produzido_mil_m3` | AG006 | volume de água produzido | 1.000 m³/ano | GTA1001 |
| `volume_agua_tratada_etas_mil_m3` | AG007 | volume de água tratada em ETAs | 1.000 m³/ano | GTA1002 |
| `volume_agua_tratada_desinfeccao_mil_m3` | AG015 | volume de água tratada por simples desinfecção | 1.000 m³/ano | GTA1003 |
| `volume_agua_tratado_mil_m3` | — | AG007 + AG015 (NA só se ambos ausentes) | 1.000 m³/ano | derivado |
| `populacao_urbana_residente_esgoto` | G06B | população urbana residente dos municípios atendidos com esgoto | habitantes | DFE0002 (planilha de esgoto) |
| `populacao_total_residente_esgoto` | G12B | população total residente dos municípios atendidos com esgoto | habitantes | DFE0001 (planilha de esgoto) |
| `populacao_total_atendida_esgoto` | ES001 | população total atendida com esgotamento sanitário | habitantes | GTE0001 + GTE0002 |
| `volume_esgoto_coletado_mil_m3` | ES005 | volume de esgotos coletado | 1.000 m³/ano | GTE1002 |
| `volume_esgoto_tratado_mil_m3` | ES006 | volume de esgotos tratado | 1.000 m³/ano | GTE1014 |
| `economias_ativas_esgoto` | ES008 | economias ativas de esgotos | economias | GTE0006 + GTE0016 |
| `numero_paralisacoes_agua` | QD002 | paralisações no sistema de distribuição de água | paralisações/ano | GTA3001 |
| `duracao_paralisacoes_horas` | QD003 | duração das paralisações | horas/ano | — (NA em 2023+) |
| `economias_atingidas_paralisacoes` | QD004 | economias ativas atingidas por paralisações | economias/ano | GTA3002 |
| `amostras_cloro_residual_fora_padrao` | QD007 | amostras de cloro residual fora do padrão | amostras/ano | — (NA em 2023+) |
| `amostras_turbidez_fora_padrao` | QD009 | amostras de turbidez fora do padrão | amostras/ano | — (NA em 2023+) |
| `economias_atingidas_interrupcoes_sistematicas` | QD015 | economias ativas atingidas por interrupções sistemáticas | economias/ano | GTA3005 |
| `amostras_coliformes_totais_fora_padrao` | QD027 | amostras de coliformes totais fora do padrão | amostras/ano | — (NA em 2023+) |
| `indice_atendimento_agua_pct` | ≈ IN055 | 100 × AG001 / G12A | % | derivado |
| `indice_atendimento_esgoto_pct` | — | 100 × ES001 / G12B (o IN056 oficial divide por G12A) | % | derivado |
| `indice_tratamento_esgoto_pct` | ≈ IN016 | 100 × ES006 / ES005 | % | derivado |

Os índices só são calculados com numerador e denominador informados e denominador > 0; valores acima de 100 % são mantidos como estão (inconsistência da fonte, comum em municípios pequenos).

## Cobertura e periodicidade

- **Territorial:** todos os municípios do Brasil (SINISA 2023: ~5.250 municípios com água e ~4.250 com esgoto). Município-ano sem nenhuma informação não entra na base.
- **Temporal:** 2000–2022 (SNIS, se as exportações estiverem presentes) e 2023+ (SINISA). `PAINEL_ANO_INICIAL` recorta para testes.
- **Periodicidade:** anual (ano de referência; a divulgação ocorre 1–2 anos depois).

## Tamanho e tempo

- SINISA 2023: ~30 MB em dois ZIPs; o servidor do gov.br é lento (≈100 KB/s observado: 3–5 min). Só as três planilhas da Base Municipal são extraídas (≈4 MB). O servidor recusa `HEAD` (403): os scripts usam apenas `GET`.
- Série Histórica: exportações de alguns MB cada (UTF-16), lidas em segundos.
- Tratamento completo: < 2 min.

## Dependências

R ≥ 4.1 com `jsonlite`, `curl` (biblioteca comum) e, no script 02, `data.table` e `readxl`. Não usa `openxlsx`.

## Como rodar

```bash
Rscript fontes/snis_sinisa/01_extracao_snis_sinisa.R      # baixa/extrai o SINISA; confere a pasta da Serie Historica
# (opcional, uma vez) exportar a Serie Historica e salvar em dados/brutos/snis_sinisa/serie_historica/
Rscript fontes/snis_sinisa/02_tratamento_snis_sinisa.R
```

Sem as exportações manuais o script 02 roda mesmo assim e a base cobre apenas 2023 em diante (aviso no log).

## Série Histórica SNIS (2000–2022): como exportar manualmente

1. Abra <https://app4.cidades.gov.br/serieHistorica/> e, no menu **Município**, escolha o relatório **Consolidado por Município** (`consolidadoMunicipio`; é o mesmo relatório cujos arquivos se chamam `ConsolidadoMunicipio-<data>.csv`).
2. **Filtros:** Tipo de informação = *Informações*; Ano de referência = **2000 a 2022** (todos); Serviço = água e esgotos; Região, Estado e Município = **todos** (não marcar nada equivale a todos).
3. **Colunas:** nas famílias *Informações gerais (GE)*, *Água (AG)*, *Esgotos (ES)* e *Qualidade (QD)* marque exatamente: `G06A, G12A, AG001, AG003, AG006, AG007, AG015, G06B, G12B, ES001, ES005, ES006, ES008, QD002, QD003, QD004, QD007, QD009, QD015, QD027`.
4. Clique em **Consultar/Gerar** e depois em **Exportar planilha**; baixe o arquivo (CSV, separador `;`, UTF-16). Se a aplicação limitar o tamanho, exporte em blocos de anos ou de famílias: vários arquivos na pasta são empilhados.
5. Salve tudo em `dados/brutos/snis_sinisa/serie_historica/` (extensão `.csv`). Os rótulos dos filtros podem variar um pouco entre versões da aplicação; o que importa é o relatório por município com as colunas acima.

Formato esperado pelo leitor (preservado do fluxo original): cabeçalho com "Código do IBGE" a mais, primeira coluna técnica vazia nas linhas de dados e delimitador final; colunas de variável começando pelo código (`AG001 - ...`); código municipal com 6 dígitos (convertido para 7 pelo dicionário oficial). Registros repetidos por município-ano-variável (prestadores distintos) são somados.

## Observações metodológicas

- **Quebra SNIS → SINISA em 2023.** O SNIS foi substituído pelo SINISA; conceitos, formulários e cobertura mudaram. Os códigos SNIS são mantidos como chave da série e as informações do SINISA são casadas pela descrição oficial (tabela acima). Não há coluna `origem`: **2000–2022 = SNIS (exportação manual); 2023 em diante = SINISA (Base Municipal)**. Compare 2022 com 2023 com ressalva.
- **População residente × atendida.** No SNIS, G06A/G12A e G06B/G12B são a população **residente** (IBGE) dos municípios atendidos; AG001/ES001 são a população **atendida**. O SINISA publica a população residente (DFE0001/DFE0002) e a atendida urbana + rural (GTA0001/GTA0002, GTE0001/GTE0002); o mapeamento respeita esses conceitos (o fluxo anterior atribuía GTA0001/GTA0002 a G06A/G12A).
- **Base Municipal do SINISA.** Consolida os prestadores de cada município; as planilhas de "prestadores locais e regionais" replicam esses dados e não são usadas (evita dupla contagem). O cabeçalho vem depois de linhas de título (detectado pela linha dos códigos `cod_IBGE`, `DFE0001`, `GTA...`).
- **Qualidade da água no SINISA.** A Base Municipal de 2023 não traz duração de paralisações (QD003) nem amostras fora do padrão (QD007/QD009/QD027): ficam `NA` a partir de 2023.
- **Ausência não é zero:** valores não informados permanecem `NA`; somas urbano + rural só resultam `NA` quando ambas as parcelas faltam.
- Se o mesmo município-ano-variável aparecer nas duas origens (ex.: exportação da Série Histórica que inclua 2023), prevalece o SINISA.
