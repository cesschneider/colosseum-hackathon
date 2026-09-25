# Fonte `senatran` — Frota de veículos por município (RENAVAM)

**Órgão:** Secretaria Nacional de Trânsito (SENATRAN), Ministério dos Transportes.
**Conjunto:** estatísticas mensais da frota registrada no RENAVAM, por município,
publicadas em duas planilhas por mês:

| Conjunto | Arquivo típico no portal | Conteúdo |
|---|---|---|
| `combustivel` | `D_Frota_por_UF_Municipio_COMBUSTIVEL_<Mês>_<Ano>.xlsx` (aba "Layout D") | UF (nome por extenso), Município, Combustível, Qtd. Veículos |
| `tipo` | `Frota_por_municipio_e_tipo_<Mês>_<Ano>.xlsx` / `frota_munic_modelo_<mês>_<ano>.xls` | UF (sigla), Município, TOTAL e 22 tipos de veículo (automóvel, motocicleta, caminhão, ônibus…) |

## Endpoints

- Páginas anuais: `https://www.gov.br/transportes/pt-br/assuntos/transito/conteudo-Senatran/frota-de-veiculos-<ANO>`
  (os links dos xlsx/xls aparecem no HTML e apontam para subpastas variadas do portal:
  `conteudo-Senatran/`, `frota-de-veiculos-<ANO>-2/`, `arquivos-renavam-<ANO>/`,
  `arquivos-senatran/estatisticas/renavam/<ANO>/<mês>/`, `centrais-de-conteudo/...-xlsx`).
- O portal responde 403 a robôs: todo acesso passa por `listar_links_pagina()` / `baixar_arquivo()`
  da biblioteca comum (User-Agent de navegador).

## Saída

`dados/tratados/senatran/senatran_municipal.csv` — **mensal** (`codigo_municipio, nome_municipio, uf, ano, mes` + indicadores).

| variável | descrição | unidade |
|---|---|---|
| `frota_total` | frota de veículos com placa (planilha por tipo) | veículos |
| `frota_total_combustivel` | total da planilha por combustível (inclui veículos sem placa/sem informação; difere de `frota_total`) | veículos |
| `frota_eletricos_bev` | 100% elétricos: ELETRICO, ELETRICO/FONTE EXTERNA, ELETRICO/FONTE INTERNA, CELULA COMBUSTIVEL | veículos |
| `frota_hibridos_phev` | HIBRIDO PLUG-IN | veículos |
| `frota_hibridos_hev` | HIBRIDO, GASOLINA/ELETRICO, GASOLINA/ALCOOL/ELETRICO, DIESEL/ELETRICO, ETANOL/ELETRICO, HIBRIDO/GAS NATURAL VEICULAR | veículos |
| `frota_combustao` | demais categorias com combustível informado | veículos |
| `frota_sem_informacao` | Sem Informação, Não Identificado, Não se Aplica, VIDE/CAMPO/OBSERVACAO (em geral reboques e semirreboques) | veículos |
| `frota_gasolina` | categoria GASOLINA | veículos |
| `frota_etanol` | categoria ALCOOL | veículos |
| `frota_flex` | ALCOOL/GASOLINA (e GASOLINA/ALCOOL) | veículos |
| `frota_diesel` | categoria DIESEL | veículos |
| `frota_gnv` | qualquer categoria com GAS NATURAL / GAS METANO (não exclusiva: inclui combinações com gasolina, álcool, diesel e híbridos) | veículos |
| `frota_automoveis`, `frota_motocicletas`, `frota_motonetas`, `frota_ciclomotores`, `frota_caminhoes`, `frota_caminhoes_trator`, `frota_caminhonetes`, `frota_camionetas`, `frota_utilitarios`, `frota_onibus`, `frota_micro_onibus`, `frota_reboques`, `frota_semi_reboques`, `frota_tratores_rodas`, `frota_tratores_esteira`, `frota_triciclos`, `frota_quadriciclos`, `frota_side_cars`, `frota_bondes`, `frota_chassis_plataforma`, `frota_outros_tipos` | uma coluna por tipo de veículo da planilha "Frota por município e tipo" | veículos |

`frota_eletricos_bev + frota_hibridos_phev + frota_hibridos_hev + frota_combustao + frota_sem_informacao = frota_total_combustivel`.
`frota_gasolina/etanol/flex/diesel` são categorias exclusivas; `frota_gnv` não.

## Cobertura temporal e periodicidade

- Mensal, **julho/2016 até o mês mais recente publicado** (`ANO_INICIAL` padrão 2016, respeita `PAINEL_ANO_INICIAL`).
- Layouts confirmados em amostras de 2014, 2016, 2017, 2018, 2019, 2020, 2023, 2024, 2025 e 2026:
  o "Layout D" (4 colunas) e a planilha por tipo (título, total geral, cabeçalho duplicado, dados) não mudaram no período.
- **Não suportado (ignorado pela extração):** 2013 (combustível em Access `.mdb` dentro de `.zip`),
  2015 e jan–jun/2016 (arquivos `.rar`). 2014 tem xlsx no mesmo layout mas o ano seguinte é `.rar`;
  para incluí-lo basta alterar `ano_inicial_efetivo(2016L)` nos dois scripts (a confirmar mês a mês).
- Meses eventualmente ausentes ou com nome fora do padrão no portal ficam sem linha na base (não há preenchimento).

## Tamanho e tempo

- Cerca de 1,0–1,3 MB por arquivo de combustível e 0,7–1,2 MB por arquivo de tipo:
  ~2 MB/mês, ~250 MB para 2016–2026 (≈ 250 arquivos), 10–30 min conforme o portal.
- O tratamento lê ~250 planilhas com `readxl` (≈ 5–10 min).

## Dependências

`readxl` (xlsx e xls), `data.table`, mais `jsonlite`/`curl` da biblioteca comum.

## Como rodar

```
Rscript fontes/senatran/01_extracao_senatran.R
Rscript fontes/senatran/02_tratamento_senatran.R
```

Variáveis de teste: `PAINEL_ANO_INICIAL=2024` (menos meses), `PAINEL_UFS="MG,ES"` (só afeta o casamento com o dicionário; os arquivos são nacionais).

## Observações metodológicas

- **Descoberta de arquivos:** a nomenclatura muda todo ano (`copy_of_`, `copy2_of_`, `Maro`/`MARO` para março,
  meses abreviados `dez_16`, sufixos `20241`, minúsculas, URLs sem extensão terminadas em `-xlsx`, uma variante `.csv`).
  O script normaliza o nome e extrai conjunto/mês/ano por expressões regulares; quando há mais de uma variante
  do mesmo mês, prefere xlsx > xls > csv. Os brutos são gravados com nome canônico `combustivel_<ano>_<mes>.<ext>` e `tipo_<ano>_<mes>.<ext>`.
- **Junção por nome + UF:** a fonte não traz código IBGE. UF vem por extenso ("MINAS GERAIS") no arquivo de combustível
  e como sigla no de tipo; o nome do município é casado via `juntar_por_nome_uf()`. Taxa observada nas amostras:
  99,2–99,4% das linhas. Os ~37 municípios restantes são grafias legadas do RENAVAM
  (ex.: PARATI/Paraty, IGUARACI/Iguaracy, SANTANA DO LIVRAMENTO/Sant'Ana do Livramento, nomes truncados em 30 caracteres);
  um segundo passo resolve prefixos e diferenças de 1–2 caracteres dentro da mesma UF quando o candidato é único.
  Ficam de fora municípios renomeados (ex.: EMBU → Embu das Artes, BOM JESUS/GO → Bom Jesus de Goiás, SANTAREM/PB → Joca Claudino)
  e as linhas "MUNICIPIO NAO INFORMADO"/"Sem Informação" (< 0,5% dos veículos); a taxa de descarte é registrada no log.
- **Totais diferentes:** a planilha por tipo cobre "veículos com placa"; a de combustível cobre todo o registro
  (2026-06: 131,8 vs 134,9 milhões). Por isso as duas totalizações são mantidas.
- Um arquivo cujo total nacional seja implausível (< 50 milhões) é descartado com aviso, evitando meses truncados.
