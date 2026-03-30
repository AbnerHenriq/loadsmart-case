# Loadsmart — Analytics Engineer Challenge

## Stack


| Componente       | Tecnologia             |
| ---------------- | ---------------------- |
| Data Warehouse   | DuckDB (arquivo local) |
| Transformação    | dbt-core + dbt-duckdb  |
| Orquestração     | Apache Airflow 2.9     |
| Visualização     | Apache Superset        |
| Análise / Export | Jupyter Notebook       |
| Infraestrutura   | Docker Compose         |


---

## Pré-requisitos

- Docker Desktop (com Docker Compose v2)
- Python 3.11+ (para rodar o dbt localmente, opcional)
- Git

---

## Estrutura do projeto

```
loadsmart/
├── data/                          # CSV de origem e arquivo DuckDB
│   └── 2026_data_challenge_ae_data.csv
├── scripts/
│   └── ingest.py                  # Carrega CSV → DuckDB raw.shipments
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── packages.yml
│   └── models/
│       ├── staging/               # stg_shipments
│       ├── intermediate/          # int_shipments_enriched
│       └── mart/                  # dim_* + fct_shipments
├── airflow/
│   └── dags/
│       └── loadsmart_pipeline.py  # ingest → dbt run → dbt test
├── docker/
│   └── superset/
│       ├── Dockerfile             # Imagem customizada com duckdb-engine
│       └── superset_config.py     # Configuração SQLite + secret key
├── notebooks/
│   └── loadsmart_analysis.ipynb  # split_lane, send_csv_email, send_csv_sftp, exports
├── docs/
│   └── raw_data_findings.md       # Achados de qualidade do dado raw
├── docker-compose.yml
├── .env
└── requirements.txt
```

---

## Como rodar o projeto

**Pré-requisito:** Docker instalado.

### Passo 1 — Clone e suba os containers

```bash
git clone <repo-url>
cd loadsmart_case
docker compose up -d
```

### Passo 2 — Execute o pipeline de dados

Acesse o **Airflow** em [http://localhost:9090](http://localhost:9090) (usuário e senha: `admin`).

Localize o pipeline `loadsmart_pipeline` e clique em **Trigger DAG** (ícone de play).
Aguarde os três passos concluírem: `ingest_csv → dbt_run → dbt_test` (~2 min).

### Passo 3 — Acesse o Superset

Assim que o pipeline terminar, o Superset em [http://localhost:8088](http://localhost:8088) estará pronto com tudo configurado automaticamente:

- Conexão com o banco de dados
- Datasets com todas as colunas
- 48 métricas organizadas em 5 domínios
- 5 dashboards prontos para uso

Login: `admin` / `admin`

> O serviço `superset-bootstrap` aguarda o pipeline terminar e configura tudo sozinho.
> Se o Superset abrir antes de o pipeline concluir, aguarde mais alguns instantes e recarregue a página.

### Localmente (sem Docker)

Crie um virtual environment para isolar as dependências do projeto:

```bash
python3 -m venv .venv
source .venv/bin/activate       # Linux/macOS
# .venv\Scripts\activate        # Windows

pip install -r requirements.txt
```

Com o venv ativo, rode o pipeline:

```bash
# Ingestão
python scripts/ingest.py

# dbt
cd dbt
dbt deps --profiles-dir .
dbt run --profiles-dir .
dbt test --profiles-dir .
```

Para desativar o venv quando terminar:

```bash
deactivate
```

### Jupyter Notebook

Com o venv ativo:

```bash
jupyter notebook notebooks/loadsmart_analysis.ipynb
```

O notebook contém:

- `split_lane(lane)` — parseia `"City,ST -> City,ST"` em dict
- `send_csv_email(df, recipients, smtp_config)` — envia CSV por e-mail via SMTP
- `send_csv_sftp(df, remote_path, credentials)` — upload de CSV via SFTP
- Query e exportação das entregas do último mês

---

## Explorando o DuckDB

O arquivo de banco fica em `data/loadsmart.duckdb` após rodar o pipeline.

### Via terminal (CLI do DuckDB)

```bash
# Instale o CLI se ainda não tiver
brew install duckdb          # macOS
# ou baixe em https://duckdb.org/docs/installation

duckdb data/loadsmart.duckdb
```

Comandos úteis dentro do CLI:

```sql
-- Listar todos os schemas e tabelas
SHOW ALL TABLES;

-- Ver estrutura de uma tabela
DESCRIBE main_mart.fct_shipments;

-- Explorar as primeiras linhas
SELECT * FROM main_mart.fct_shipments LIMIT 10;
SELECT * FROM main_mart.dim_carrier   LIMIT 10;
SELECT * FROM main_mart.dim_location  LIMIT 10;
SELECT * FROM main_mart.dim_date      LIMIT 5;

-- Sair
.quit
```

### Via Python (com o venv ativo)

```python
import duckdb

con = duckdb.connect("data/loadsmart.duckdb")
df = con.execute("SELECT * FROM main_mart.fct_shipments LIMIT 20").df()
print(df)
```

### Via DBeaver

1. Abra o DBeaver e clique em **New Database Connection**
2. Selecione **DuckDB**
  - Se não aparecer, vá em **Driver Manager → New** e adicione o driver JDBC do DuckDB
  - Download do driver: [duckdb.org/docs/api/java](https://duckdb.org/docs/api/java)
3. Em **Path**, aponte para o arquivo: `/Users/abner.rodrigues/cases/loadsmart_case/data/loadsmart.duckdb`
4. Clique em **Test Connection** → **Finish**
5. Na árvore de objetos, navegue em: `loadsmart.duckdb → main_mart → Tables`

> **Atenção:** DuckDB só permite **uma conexão de escrita por vez**. Se o Airflow ou o dbt estiver rodando com o arquivo aberto, o DBeaver pode se conectar em modo read-only. Encerre os outros processos antes de abrir no DBeaver se precisar editar dados.

---

## Modelo dimensional (Star Schema)

```
                    dim_date
                      │
          dim_carrier  │  dim_shipper
               │       │       │
               └───fct_shipments───┘
                      │
                 dim_location
              (pickup + delivery)
```


| Tabela          | Schema       | Linhas | Descrição                                    |
| --------------- | ------------ | ------ | -------------------------------------------- |
| `raw.shipments` | raw          | 5.361  | Dados brutos do CSV                          |
| `int_shipments` | intermediate | 5.357  | Deduplicado + métricas derivadas             |
| `dim_carrier`   | mart         | 2.203  | Carriers únicos + sentinel "Unknown"         |
| `dim_shipper`   | mart         | 94     | Shippers únicos                              |
| `dim_location`  | mart         | 988    | Cidades/estados únicos (origem + destino)    |
| `dim_date`      | mart         | 438    | Calendário cobrindo todo o período dos dados |
| `fct_shipments` | mart         | 5.357  | Fato central — 1 linha por shipment          |


### Camadas dbt


| Camada       | Materialização | Propósito                               |
| ------------ | -------------- | --------------------------------------- |
| staging      | view           | Limpeza, tipagem, parse do campo `lane` |
| intermediate | table          | Deduplicação, métricas derivadas        |
| mart         | table          | Dimensões e fato prontos para análise   |


---

## Métricas e Dashboards (Superset)

### Dataset virtual

No Superset, crie um **Virtual Dataset** (SQL) para pré-joinar as dimensões de nome:

```sql
SELECT
    f.*,
    dc.carrier_name,
    ds.shipper_name
FROM main_mart.fct_shipments f
LEFT JOIN main_mart.dim_carrier  dc ON f.carrier_sk = dc.carrier_sk
LEFT JOIN main_mart.dim_shipper  ds ON f.shipper_sk = ds.shipper_sk
```

Configure `delivered_at` como **coluna temporal** do dataset.

### Métricas calculadas

Adicionar em **Edit Dataset → Metrics** no Superset:

> **Regra:** nunca pré-calcular razões — sempre somar componentes antes de dividir.

#### Domínio 1 — Financeiro


| Métrica            | Label                 | Domínio    | Owner         | Expressão SQL                      |
| ------------------ | --------------------- | ---------- | ------------- | ---------------------------------- |
| `total_revenue`    | Receita total         | Financeiro | CFO / Pricing | `SUM(book_price)`                  |
| `total_cost`       | Custo total           | Financeiro | CFO / Pricing | `SUM(source_price)`                |
| `total_pnl`        | PnL total             | Financeiro | CFO / Pricing | `SUM(pnl)`                         |
| `avg_book_price`   | Book price médio      | Financeiro | CFO / Pricing | `AVG(book_price)`                  |
| `avg_pnl`          | PnL médio             | Financeiro | CFO / Pricing | `AVG(pnl)`                         |
| `total_mileage`    | Mileage total         | Financeiro | CFO / Pricing | `SUM(mileage)`                     |
| `avg_mileage`      | Mileage médio         | Financeiro | CFO / Pricing | `AVG(mileage)`                     |
| `margin_pct`       | Margem %              | Financeiro | CFO / Pricing | `SUM(pnl) / SUM(book_price)`       |
| `cost_per_mile`    | Custo por milha       | Financeiro | CFO / Pricing | `SUM(source_price) / SUM(mileage)` |
| `revenue_per_mile` | Receita por milha     | Financeiro | CFO / Pricing | `SUM(book_price) / SUM(mileage)`   |
| `pnl_per_mile`     | PnL por milha         | Financeiro | CFO / Pricing | `SUM(pnl) / SUM(mileage)`          |
| `spread_price`     | Spread book vs source | Financeiro | CFO / Pricing | `AVG(book_price - source_price)`   |


#### Domínio 2 — Volume e Funil


| Métrica                  | Label                           | Domínio        | Owner       | Expressão SQL                                   |
| ------------------------ | ------------------------------- | -------------- | ----------- | ----------------------------------------------- |
| `total_loads`            | Total de cargas                 | Volume / Funil | Ops Manager | `COUNT(loadsmart_id)`                           |
| `cancelled_loads`        | Cargas canceladas               | Volume / Funil | Ops Manager | `SUM(load_was_cancelled::int)`                  |
| `active_loads`           | Cargas ativas                   | Volume / Funil | Ops Manager | `SUM((NOT load_was_cancelled)::int)`            |
| `contracted_loads`       | Cargas contratadas              | Volume / Funil | Ops Manager | `SUM(contracted_load::int)`                     |
| `cancellation_rate`      | Taxa de cancelamento            | Volume / Funil | Ops Manager | `SUM(load_was_cancelled::int) * 1.0 / COUNT(*)` |
| `contracted_load_rate`   | % cargas contratadas            | Volume / Funil | Produto     | `SUM(contracted_load::int) * 1.0 / COUNT(*)`    |
| `avg_lead_time_booking`  | Lead time quote → book (horas)  | Volume / Funil | Produto     | `AVG(datediff('hour', quote_at, booked_at))`    |
| `avg_lead_time_sourcing` | Lead time book → source (horas) | Volume / Funil | Produto     | `AVG(datediff('hour', booked_at, sourced_at))`  |
| `avg_transit_days`       | Transit time médio (dias)       | Volume / Funil | Ops Manager | `AVG(datediff('day', pickup_at, delivered_at))` |


#### Domínio 3 — Performance de Carrier


| Métrica                  | Label                          | Domínio | Owner       | Expressão SQL                                                                                    |
| ------------------------ | ------------------------------ | ------- | ----------- | ------------------------------------------------------------------------------------------------ |
| `on_time_pickup_count`   | Coletas on-time (contagem)     | Carrier | Ops Manager | `SUM(carrier_on_time_to_pickup::int)`                                                            |
| `on_time_delivery_count` | Entregas on-time (contagem)    | Carrier | Ops Manager | `SUM(carrier_on_time_to_delivery::int)`                                                          |
| `on_time_overall_count`  | On-time geral (contagem)       | Carrier | Ops Manager | `SUM(carrier_on_time_overall::int)`                                                              |
| `total_carrier_drops`    | Total de drops                 | Carrier | Ops Manager | `SUM(carrier_dropped_us_count)`                                                                  |
| `vip_carrier_loads`      | Cargas com VIP carrier         | Carrier | Ops Manager | `SUM(vip_carrier::int)`                                                                          |
| `on_time_pickup_rate`    | On-time to pickup %            | Carrier | Ops Manager | `SUM(carrier_on_time_to_pickup::int) * 1.0 / COUNT(*)`                                           |
| `on_time_delivery_rate`  | On-time to delivery %          | Carrier | Ops Manager | `SUM(carrier_on_time_to_delivery::int) * 1.0 / COUNT(*)`                                         |
| `on_time_overall_rate`   | On-time overall %              | Carrier | Ops Manager | `SUM(carrier_on_time_overall::int) * 1.0 / COUNT(*)`                                             |
| `avg_drops_per_carrier`  | Média de drops por carrier     | Carrier | Ops Manager | `SUM(carrier_dropped_us_count) * 1.0 / COUNT(*)`                                                 |
| `vip_carrier_rate`       | % cargas com VIP carrier       | Carrier | Ops Manager | `SUM(vip_carrier::int) * 1.0 / COUNT(*)`                                                         |
| `on_time_delta`          | Gap pickup vs delivery on-time | Carrier | Ops Manager | `(SUM(carrier_on_time_to_pickup::int) - SUM(carrier_on_time_to_delivery::int)) * 1.0 / COUNT(*)` |


#### Domínio 4 — Autonomia Operacional


| Métrica                    | Label                        | Domínio   | Owner   | Expressão SQL                                                                               |
| -------------------------- | ---------------------------- | --------- | ------- | ------------------------------------------------------------------------------------------- |
| `autonomously_booked`      | Bookings autônomos           | Automação | Produto | `SUM(load_booked_autonomously::int)`                                                        |
| `autonomously_sourced`     | Sourcings autônomos          | Automação | Produto | `SUM(load_sourced_autonomously::int)`                                                       |
| `fully_autonomous_loads`   | Cargas 100% autônomas        | Automação | Produto | `SUM((load_booked_autonomously AND load_sourced_autonomously)::int)`                        |
| `autonomous_booking_rate`  | Taxa de booking autônomo %   | Automação | Produto | `SUM(load_booked_autonomously::int) * 1.0 / COUNT(*)`                                       |
| `autonomous_sourcing_rate` | Taxa de sourcing autônomo %  | Automação | Produto | `SUM(load_sourced_autonomously::int) * 1.0 / COUNT(*)`                                      |
| `fully_autonomous_rate`    | Taxa 100% autônoma %         | Automação | Produto | `SUM((load_booked_autonomously AND load_sourced_autonomously)::int) * 1.0 / COUNT(*)`       |
| `human_intervention_rate`  | Taxa de intervenção humana % | Automação | Produto | `1.0 - SUM((load_booked_autonomously AND load_sourced_autonomously)::int) * 1.0 / COUNT(*)` |


#### Domínio 5 — Tracking e Visibilidade


| Métrica                    | Label                         | Domínio  | Owner   | Expressão SQL                                                                                               |
| -------------------------- | ----------------------------- | -------- | ------- | ----------------------------------------------------------------------------------------------------------- |
| `mobile_tracked`           | Cargas com mobile tracking    | Tracking | Produto | `SUM(has_mobile_app_tracking::int)`                                                                         |
| `macropoint_tracked`       | Cargas com Macropoint         | Tracking | Produto | `SUM(has_macropoint_tracking::int)`                                                                         |
| `edi_tracked`              | Cargas com EDI                | Tracking | Produto | `SUM(has_edi_tracking::int)`                                                                                |
| `any_tracked`              | Cargas com algum tracking     | Tracking | Produto | `SUM((has_mobile_app_tracking OR has_macropoint_tracking OR has_edi_tracking)::int)`                        |
| `mobile_tracking_rate`     | Cobertura mobile app %        | Tracking | Produto | `SUM(has_mobile_app_tracking::int) * 1.0 / COUNT(*)`                                                        |
| `macropoint_tracking_rate` | Cobertura Macropoint %        | Tracking | Produto | `SUM(has_macropoint_tracking::int) * 1.0 / COUNT(*)`                                                        |
| `edi_tracking_rate`        | Cobertura EDI %               | Tracking | Produto | `SUM(has_edi_tracking::int) * 1.0 / COUNT(*)`                                                               |
| `total_tracking_coverage`  | Cobertura total de tracking % | Tracking | Produto | `SUM((has_mobile_app_tracking OR has_macropoint_tracking OR has_edi_tracking)::int) * 1.0 / COUNT(*)`       |
| `blind_shipment_rate`      | Cargas sem nenhum tracking %  | Tracking | Produto | `1.0 - SUM((has_mobile_app_tracking OR has_macropoint_tracking OR has_edi_tracking)::int) * 1.0 / COUNT(*)` |


### Dashboard 1 — Saúde operacional

**Audiência:** ops manager · **Pergunta:** alguma coisa quebrou?


| Chart                      | Tipo           | Métrica(s)                                     | Dimensão              |
| -------------------------- | -------------- | ---------------------------------------------- | --------------------- |
| On-time rate               | KPI            | `on_time_overall_rate`                         | —                     |
| Total de cargas            | KPI            | `COUNT(loadsmart_id)`                          | —                     |
| Transit time médio         | KPI            | `AVG(lead_time_days)`                          | —                     |
| Taxa de cancelamento       | KPI            | `cancellation_rate`                            | —                     |
| On-time rate por carrier   | Bar horizontal | `on_time_overall_rate`                         | `carrier_name`        |
| Evolução on-time mensal    | Line           | `on_time_overall_rate`                         | mês de `delivered_at` |
| Mix por equipment type     | Donut          | `COUNT(*)`                                     | `equipment_type`      |
| Pickup vs delivery on-time | Bar agrupado   | `on_time_pickup_rate`, `on_time_delivery_rate` | `carrier_name`        |


### Dashboard 2 — Saúde financeira

**Audiência:** CFO / pricing analyst · **Pergunta:** onde ganhamos e perdemos?


| Chart                        | Tipo           | Métrica(s)               | Dimensão              |
| ---------------------------- | -------------- | ------------------------ | --------------------- |
| PnL total                    | KPI            | `SUM(pnl)`               | —                     |
| Margem %                     | KPI            | `margin_pct`             | —                     |
| Custo por milha              | KPI            | `cost_per_mile`          | —                     |
| Book price médio             | KPI            | `AVG(book_price)`        | —                     |
| Margem por sourcing channel  | Bar horizontal | `margin_pct`             | `sourcing_channel`    |
| PnL por shipper (top 10)     | Bar horizontal | `SUM(pnl)`               | `shipper_name`        |
| Mileage vs PnL               | Scatter        | `pnl_per_mile`           | `carrier_name`        |
| Evolução PnL e margem mensal | Line           | `SUM(pnl)`, `margin_pct` | mês de `delivered_at` |


### Dashboard 3 — Eficiência & Autonomia

**Audiência:** produto / liderança · **Pergunta:** a automação está evoluindo?


| Chart                          | Tipo           | Métrica(s)                                                             | Dimensão              |
| ------------------------------ | -------------- | ---------------------------------------------------------------------- | --------------------- |
| Taxa 100% autônoma             | KPI            | `fully_autonomous_rate`                                                | —                     |
| Cobertura de tracking          | KPI            | `total_tracking_coverage`                                              | —                     |
| % cargas VIP carrier           | KPI            | `vip_carrier_rate`                                                     | —                     |
| Cargas sem tracking            | KPI            | `blind_shipment_rate`                                                  | —                     |
| Autonomia por canal            | Bar horizontal | `fully_autonomous_rate`                                                | `sourcing_channel`    |
| Cobertura por tipo de tracking | Bar agrupado   | `mobile/macropoint/edi_rate`                                           | —                     |
| Evolução autonomia mensal      | Line           | `fully_autonomous_rate`                                                | mês de `delivered_at` |
| Carriers ranqueados            | Tabela         | `on_time_overall_rate`, `fully_autonomous_rate`, `blind_shipment_rate` | `carrier_name`        |


---

## Qualidade dos dados

Os achados de qualidade encontrados na camada raw estão documentados em
[docs/raw_data_findings.md](docs/raw_data_findings.md).

Resumo dos principais pontos:


| Achado                                              | Linhas | Severidade |
| --------------------------------------------------- | ------ | ---------- |
| Coluna `has_mobile_app_tracking` duplicada no CSV   | todas  | Alta       |
| `pnl` inconsistente com `book_price - source_price` | 24     | Alta       |
| `delivered_at` anterior a `pickup_at`               | 467    | Alta       |
| `loadsmart_id` duplicado (linhas idênticas)         | 8      | Média      |
| `carrier_name` nulo (maioria canceladas)            | 499    | Média      |
| `mileage = 0` em cargas não canceladas              | 45     | Média      |


Os testes dbt estão configurados como `warn` (não bloqueantes) para os achados
conhecidos, permitindo que o pipeline rode enquanto os problemas são investigados.

---

## Parar o ambiente

```bash
docker compose down
```

Para remover também os volumes (dados do Postgres de metadados do Airflow):

```bash
docker compose down -v
```

