# MapBiomas — cobertura e uso da terra por município

## Fonte

- **Órgão/projeto:** MapBiomas Brasil (Coleção 30 m vigente; em setembro de 2026, Coleção 11, série 1985–2025).
- **Conjunto:** "Biomas, Estados e Municípios | Cobertura 30m" — tabela com a área (ha) de cada classe de cobertura e uso da terra por bioma × estado × município, uma coluna por ano.
- **Página de descoberta:** <https://brasil.mapbiomas.org/estatisticas/>. A planilha fica hospedada no Google Drive; o script localiza na página a linha da tabela de downloads que fala em municípios, cobertura e biomas, extrai o `id` do Drive e o número da coleção.
- **Download:** `https://drive.usercontent.google.com/download?id=<id>&export=download&confirm=t`.
- **Reserva:** se a página mudar e a descoberta falhar, o script usa `PAINEL_MAPBIOMAS_DRIVE_ID` / `PAINEL_MAPBIOMAS_COLECAO` (padrão: id da Coleção 11 conferido em 2026-09) e avisa no log.
- **Licença:** CC BY 4.0 (citar "Projeto MapBiomas – Coleção N").

## Arquivos

| Script | Papel |
|---|---|
| `01_extracao_mapbiomas.R` | descobre o link, baixa e preserva `dados/brutos/mapbiomas/mapbiomas_cobertura_municipios_col<colecao>.xlsx` (uma coleção nova gera arquivo novo; a anterior fica guardada) |
| `02_tratamento_mapbiomas.R` | lê a aba `COVERAGE_<colecao>` da coleção mais recente disponível, agrega por município-ano e grava `dados/tratados/mapbiomas/mapbiomas_municipal.csv` + `mapbiomas_dicionario_variaveis.csv` |

## Indicadores (`mapbiomas_municipal.csv`, uma linha por município-ano)

| variável | descrição | unidade |
|---|---|---|
| `area_floresta_ha` | Floresta (classe de nível 1: formação florestal, savânica, mangue, restinga arbórea…) | hectares |
| `area_formacao_natural_nao_florestal_ha` | Formação natural não florestal (nível 1: campo, área úmida, apicum, afloramento rochoso…) | hectares |
| `area_agropecuaria_ha` | Agropecuária (nível 1 = pastagem + agricultura + silvicultura + mosaico de usos) | hectares |
| `area_nao_vegetada_ha` | Área não vegetada (nível 1: praia/duna, área urbana, mineração, outras) | hectares |
| `area_agua_ha` | Corpos d'água (nível 1) | hectares |
| `area_nao_observada_ha` | Não observado (nível 1) | hectares |
| `area_pastagem_ha` | Pastagem (subclasse 3.1) | hectares |
| `area_agricultura_ha` | Agricultura (subclasse 3.2: lavouras temporárias e perenes) | hectares |
| `area_silvicultura_ha` | Silvicultura (subclasse 3.3) | hectares |
| `area_mosaico_de_usos_ha` | Mosaico de usos (subclasse 3.4) | hectares |
| `area_urbana_ha` | Área urbanizada (subclasse 4.2) | hectares |
| `area_mineracao_ha` | Mineração (subclasse 4.3) | hectares |
| `area_total_ha` | Soma das seis classes de nível 1 (≈ área mapeada do município) | hectares |

As seis classes de nível 1 são mutuamente exclusivas e somam `area_total_ha`; as subclasses são recortes das classes 3 e 4 e **não** devem ser somadas às de nível 1.

## Cobertura e periodicidade

- **Territorial:** todos os municípios do Brasil (código IBGE de 7 dígitos vindo da coluna `geocode`; coleções antigas sem `geocode` são casadas por nome + UF).
- **Temporal:** 1985 até o último ano da coleção (Coleção 11: 2025). `PAINEL_ANO_INICIAL` recorta a série para testes.
- **Periodicidade:** anual. Cada coleção nova **reprocessa toda a série histórica** (valores de anos antigos mudam entre coleções); a base tratada usa sempre uma única coleção, a mais recente baixada.

## Tamanho e tempo

- Um único `.xlsx` nacional, da ordem de dezenas de MB (município × classe folha × bioma, ~40 colunas de ano). Download de poucos minutos; a leitura com `readxl` leva alguns minutos e usa cerca de 1–2 GB de RAM.
- O Google Drive pode devolver uma página HTML (aviso de antivírus/cota) em vez do arquivo: o validador exige ≥ 1 MB e assinatura de pacote OOXML (`PK`) e o download é refeito.

## Dependências

R ≥ 4.1 com `jsonlite`, `curl` (biblioteca comum) e, no script 02, `data.table` e `readxl` (`fontes/00_comum/instalar_dependencias.R`). Não usa `openxlsx`, `xml2` nem `zip`.

## Como rodar

```bash
Rscript fontes/mapbiomas/01_extracao_mapbiomas.R
Rscript fontes/mapbiomas/02_tratamento_mapbiomas.R
```

## Observações metodológicas

- **Aba e níveis usados:** aba `COVERAGE_<colecao>`; cada linha é uma classe folha com a hierarquia em `class_level_1..4`. A agregação soma as linhas por município (inclusive quando o município aparece em mais de um bioma) para cada classe de nível 1 e para as subclasses listadas. O casamento das classes é por palavra-chave no rótulo em inglês (`Forest`, `Non Forest Natural Formation`/`Herbaceous and Shrubby Vegetation`, `Farming`, `Non vegetated area`, `Water`, `Not Observed`; `Pasture`, `Agriculture`, `Forest Plantation`, `Mosaic`, `Urban`, `Mining`), pois a numeração e a grafia mudam entre coleções. Classe de nível 1 sem mapeamento interrompe o script.
- **Ausência não é zero:** se todas as parcelas de um município-classe-ano estiverem vazias na planilha, o agregado fica `NA`; classe sem linha para o município (planilha esparsa) recebe zero estrutural. `area_total_ha` fica `NA` quando alguma classe de nível 1 publicada estiver vazia.
- **Área total:** é a soma das classes de nível 1 (área mapeada), não a área territorial oficial do IBGE; pequenas diferenças são esperadas.
- **Quebras entre coleções:** não se deve comparar valores de coleções diferentes; ao atualizar a coleção, toda a série é substituída.
