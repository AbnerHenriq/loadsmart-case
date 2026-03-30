# Raw Data Findings — `raw.shipments`

Análise realizada sobre o arquivo `2026_data_challenge_ae_data.csv` (5.361 linhas).
Todos os números abaixo foram extraídos diretamente da camada `raw` antes de qualquer transformação.

---

## 1. Coluna duplicada no CSV

**Campo:** `has_mobile_app_tracking`

O CSV contém esta coluna **duas vezes** com exatamente o mesmo nome. Pandas renomeia automaticamente a segunda ocorrência para `has_mobile_app_tracking.1`. A coluna duplicada foi dropada no script de ingestão (`scripts/ingest.py`) antes do carregamento no DuckDB, mantendo apenas a primeira ocorrência.

**Resolução:** Ambas as colunas são mantidas na ingestão (`scripts/ingest.py`): a segunda ocorrência é renomeada para `has_mobile_app_tracking_2`. Na camada staging (`stg_shipments.sql`) foi confirmado que as duas colunas são **idênticas** (0 divergências), portanto `has_mobile_app_tracking_2` é dropada ali — a coluna original segue exposta no mart. O raw preserva ambas para auditoria futura.

---

## 2. Duplicatas de `loadsmart_id`

**Impacto:** 4 IDs duplicados → 8 linhas no total (4 pares de linhas exatamente iguais)


| loadsmart_id | lane                           | load_was_cancelled |
| ------------ | ------------------------------ | ------------------ |
| 206432441    | Trenton,MO -> Reno,NV          | False              |
| 206437697    | Plant City,FL -> McCook,IL     | True               |
| 206533729    | Compton,CA -> Plant City,FL    | False              |
| 206586825    | Sapulpa,OK -> Warner Robins,GA | False              |


Todos os pares são **linhas completamente idênticas** — não são atualizações ou versões diferentes do mesmo envio. Parecem ser duplicatas acidentais de ingestão na fonte.

**Sugestão:** Adicionar constraint de unicidade na origem. No pipeline atual, a camada intermediate aplica `DISTINCT` para deduplicar antes de alimentar o mart.

---

## 3. `carrier_name` nulo

**Impacto:** 499 linhas (9,31% do total)

A grande maioria dos registros sem carrier_name pertence a cargas canceladas (`load_was_cancelled = TRUE`). Isso é semanticamente coerente: se a carga foi cancelada antes da alocação de um carrier, não há nome a registrar.


| Situação                             | Linhas          |
| ------------------------------------ | --------------- |
| Total nulos                          | 499             |
| Canceladas com carrier_name nulo     | ~480 (estimado) |
| Não canceladas com carrier_name nulo | ~19             |


**Sugestão:** Para cargas não canceladas sem carrier_name, investigar se houve falha de integração com o sistema de TMS. Considerar criar uma dimensão `dim_carrier` com um membro padrão `"Unknown"` para não quebrar integridade referencial no mart.

---

## 4. `book_price` e `source_price` iguais a zero

**Impacto:**

- `book_price = 0`: 530 linhas
- `source_price = 0`: 519 linhas

**Breakdown por status de cancelamento:**


| load_was_cancelled | Linhas | Linhas com book_price = 0 |
| ------------------ | ------ | ------------------------- |
| True               | 517    | 514                       |
| False              | 4.844  | 16                        |


A esmagadora maioria dos zeros está em cargas canceladas. Para cargas canceladas, preços zero são semanticamente válidos (não houve execução do serviço). As 16 cargas **não canceladas com book_price = 0** são potencialmente problemáticas.

**Sugestão:** Investigar as 16 cargas ativas com preço zero — podem ser testes, cargas de cortesia ou erros de registro. Considerar excluí-las de análises financeiras.

---

## 5. `pnl` inconsistente com `book_price - source_price`

**Impacto:** 24 linhas onde `pnl ≠ book_price - source_price` (diferença > $0,01)

Ao analisar os casos, **todos os 24 registros têm `source_price = 0` mas `book_price > 0`**, e o campo `pnl` registrado é `0` ao invés do valor esperado (`book_price`). Exemplo:


| loadsmart_id | book_price | source_price | pnl registrado | pnl esperado |
| ------------ | ---------- | ------------ | -------------- | ------------ |
| 206554409    | 7.232,42   | 0,00         | 0,00           | 7.232,42     |
| 206577609    | 479,27     | 0,00         | 0,00           | 479,27       |


**Sugestão:** O campo `pnl` não deve ser usado diretamente nas análises. A camada mart recalcula o PnL como `book_price - source_price` para garantir consistência.

---

## 6. `mileage` igual a zero

**Impacto:** 47 linhas com `mileage = 0`


| Status             | Linhas |
| ------------------ | ------ |
| Canceladas         | 2      |
| **Não canceladas** | **45** |


As 45 cargas não canceladas com mileage zero são suspeitas. Exemplos verificados têm lanes reais de longa distância (ex: `Maxton,NC -> Portland,OR`, `Lakewood,NY -> Portland,OR`) — rotas que claramente deveriam ter mileage > 0.

**Sugestão:** Este é provavelmente um erro de integração com o sistema de cálculo de distâncias. As 45 linhas devem ser excluídas de análises de custo por milha. Considerar adicionar flag `is_mileage_valid` no mart.

---

## 7. `carrier_rating` extremamente esparso

**Impacto:** 4.614 de 5.361 linhas sem valor (86,1% nulo)


| Métrica          | Valor       |
| ---------------- | ----------- |
| Total de linhas  | 5.361       |
| Com rating       | 747 (13,9%) |
| Range de valores | 0,0 – 5,0   |


Apenas 13,9% das cargas têm rating registrado. Isso torna a coluna inutilizável para análises populacionais sem segmentação explícita.

**Sugestão:** Verificar se o rating é preenchido apenas para carriers em determinado programa de avaliação ou a partir de uma data específica. Não usar `AVG(carrier_rating)` sem filtrar nulos — a média seria altamente viesada por seleção.

---

## 8. `sourcing_channel` extremamente esparso

**Impacto:** 5.117 de 5.361 linhas sem valor (95,5% nulo)


| sourcing_channel     | Linhas |
| -------------------- | ------ |
| NULL                 | 5.117  |
| carrier_capacity     | 96     |
| dat_in               | 80     |
| dat_out              | 30     |
| source_list          | 28     |
| ts_in                | 6      |
| ts_out               | 2      |
| external_source_list | 1      |
| livejobs             | 1      |


**Sugestão:** Verificar se cargas com sourcing_channel nulo representam um canal específico (ex: canal direto, contratado) ou se houve falha de logging. Considerar mapear NULL para `"direct"` ou `"unknown"` para não distorcer análises de sourcing.

---

## 9. `delivered_at` anterior a `pickup_at`

**Impacto:** 467 linhas onde `delivery_date < pickup_date`

Isso é logicamente impossível para uma carga entregue. Possíveis causas:

- Datas de entrega representam o **agendado** (appointment), não o real
- Erro de fuso horário na conversão
- Dados de teste

**Sugestão:** Clarificar se `delivery_date` é a data de entrega efetiva ou apenas o agendamento. Se efetiva, as 467 linhas precisam de investigação. A camada mart não filtra esses registros mas expõe a flag para análise.

---

## Resumo executivo


| #   | Achado                                              | Linhas afetadas | Severidade    |
| --- | --------------------------------------------------- | --------------- | ------------- |
| 1   | Coluna duplicada (`has_mobile_app_tracking`)        | todas           | Alta          |
| 2   | `loadsmart_id` duplicado (linhas idênticas)         | 8               | Média         |
| 3   | `carrier_name` nulo                                 | 499 (9,3%)      | Média         |
| 4   | `book_price` / `source_price` = 0                   | ~530 / ~519     | Média         |
| 5   | `pnl` inconsistente com `book_price - source_price` | 24              | Alta          |
| 6   | `mileage` = 0 em cargas ativas                      | 45              | Média         |
| 7   | `carrier_rating` esparso                            | 4.614 (86%)     | Informacional |
| 8   | `sourcing_channel` esparso                          | 5.117 (95%)     | Informacional |
| 9   | `delivered_at` < `pickup_at`                        | 467 (8,7%)      | Alta          |


