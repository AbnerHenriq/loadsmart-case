# CLAUDE.md — Loadsmart Analytics Case

Contexto persistente para sessões de IA neste projeto.

---

## Projeto

Pipeline de analytics para dados de shipments da Loadsmart.
Stack: **DuckDB + dbt-core + Apache Airflow + Apache Superset**, tudo em Docker Compose.

Fluxo: `CSV → raw.shipments (ingest.py) → stg_ → int_ → mart.* → Superset dashboards`

Para subir o ambiente: `make setup` (Docker necessário).
Para resetar do zero: `make reset`.

---

## Convenções SQL

### Palavras-chave em MAIÚSCULO

Todas as palavras reservadas SQL devem ser escritas em MAIÚSCULO nos arquivos dbt:
`SELECT`, `FROM`, `AS`, `WHERE`, `WITH`, `JOIN`, `ON`, `CASE`, `WHEN`, `THEN`, `ELSE`, `END`,
`QUALIFY`, `PARTITION BY`, `ORDER BY`, `GROUP BY`, `COALESCE`, `NULLIF`, `TRIM`, `ROUND`, etc.

### Aliases de coluna em UPPERCASE no mart

Toda coluna exposta nos modelos `mart/` deve ter alias em `UPPERCASE`.
A Superset API retorna os nomes exatamente como estão no DuckDB — o bootstrap usa esses
nomes para `groupby`, filtros e métricas. Divergência de case quebra charts em runtime.

```sql
-- CORRETO
SELECT carrier_name AS CARRIER_NAME FROM ...
```

### Timestamps via macro `parse_ts`

Nunca usar `strptime()` diretamente. Usar o macro em `dbt/macros/parse_ts.sql`:

```sql
{{ parse_ts('book_date') }}   -- não: strptime(book_date, '%m/%d/%Y %H:%M')
```

### Refs e sources sem hardcode

```sql
FROM {{ source('raw', 'shipments') }}   -- não: FROM raw.shipments
FROM {{ ref('fct_shipments') }}         -- não: FROM mart.fct_shipments
```

### Outras regras obrigatórias

- **CTEs** sobre subqueries inline
- **QUALIFY** para deduplicação (`ROW_NUMBER() OVER (PARTITION BY ...)`)
- **`NULLIF(TRIM(col), '')`** para colunas string vindas de fonte externa
- **`COALESCE(fk, 'unknown-...')`** para FKs de dimensão que podem ser NULL
- **`CASE WHEN denominador > 0 THEN ... ELSE NULL END`** antes de qualquer divisão
- **`SELECT *` proibido** em modelos `mart/` (listar colunas explicitamente)

---

## Fronteiras de camada dbt

| Camada | Schema DuckDB | Materialização | Responsabilidade |
|--------|--------------|----------------|-----------------|
| `staging/` | `staging` | view | Parse, limpeza, tipagem, dedup |
| `intermediate/` | `intermediate` | table | Métricas derivadas, enriquecimento |
| `mart/` | `mart` | table | Fact/dim expostos ao Superset |

Lógica de negócio **nunca** em staging. Joins com dimensões finais **nunca** em intermediate.

---

## Nomenclatura de documentos

| Prefixo | Tipo | Onde fica |
|---------|------|-----------|
| `rbk0XX` | Runbook (guia de referência) | `docs/runbooks/` |
| `0XX` | Comando Claude invocável | `.claude/commands/` |
| `cur0XX` | Regra do Cursor | `.cursor/rules/` |

Análises exploratórias ficam em `docs/analysis/` (sem prefixo numérico).

---

## Comandos Claude disponíveis

| Comando | O que faz |
|---------|-----------|
| `/001-sql-best-practices` | Revisa SQL contra as 10 regras do projeto |
| `/002-pr-review` | Revisão completa de PR: SQL + camadas + testes + impacto nos dados |
| `/003-create-dashboard` | Executa o runbook `rbk005` para criar dashboard no Superset |

O `/002-pr-review` chama `/001-sql-best-practices` automaticamente para todo `.sql` alterado.

---

## Dados — notas importantes

- **5.357 shipments** após deduplicação (4 pares de linhas idênticas removidos em staging)
- **`carrier_sk = 'unknown-carrier'`** é o sentinel para cargas sem carrier (499 casos, maioria cancelada)
- **PnL** é sempre recalculado como `book_price - source_price` — o campo `pnl` do raw tem 24 inconsistências
- **`IS_MILEAGE_VALID`** filtra as 45 cargas com `mileage = 0` para análises de custo/milha
- **`DELIVERED_ON_TIME`** inclui 467 casos onde `delivered_at < pickup_at` — flag exposta, não filtrada
- 9 achados de qualidade documentados em `docs/analysis/raw-data-findings.md`

---

## Superset

- UI: `http://localhost:8088` (admin / admin)
- Airflow: `http://localhost:9090` (admin / admin)
- Dataset principal: `fct_shipments` (id=1)
- Bootstrap idempotente: `scripts/superset_bootstrap.py` (pode ser re-executado com segurança)
- Pitfall crítico: usar `echarts_timeseries_bar` (não `bar`); colunas em `groupby` devem ser UPPERCASE

Runbooks de referência: `docs/runbooks/rbk001` a `rbk005`.
