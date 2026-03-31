AIRFLOW_URL  ?= http://localhost:9090
SUPERSET_URL ?= http://localhost:8088
AIRFLOW_USER ?= admin
AIRFLOW_PASS ?= admin
DAG_ID       := loadsmart_pipeline

.DEFAULT_GOAL := help

# ── Help ──────────────────────────────────────────────────────────────────────

.PHONY: help
help:
	@echo ""
	@echo "  Loadsmart Case — comandos disponíveis"
	@echo ""
	@echo "  make setup          Sobe tudo do zero (Docker → pipeline → Superset)"
	@echo "  make reset          Dropa tudo e refaz do zero (teardown + setup)"
	@echo "  make up             Sobe os containers"
	@echo "  make pipeline       Executa o pipeline de dados no Airflow"
	@echo "  make status         Mostra estado dos containers e do último pipeline"
	@echo "  make teardown       Para e remove containers, volumes e imagens"
	@echo "  make open           Abre Airflow e Superset no navegador"
	@echo "  make logs-pipeline  Logs do pipeline de dados"
	@echo "  make logs-bootstrap Logs da configuração do Superset"
	@echo ""

# ── Setup completo ────────────────────────────────────────────────────────────

.PHONY: setup
setup: up wait-airflow trigger-pipeline wait-pipeline
	@echo ""
	@echo "  ✓ Pipeline concluído. O Superset está configurando os dashboards..."
	@echo "  ✓ Acesse http://localhost:8088 em instantes (admin / admin)"
	@echo ""

# ── Docker ────────────────────────────────────────────────────────────────────

.PHONY: up
up:
	@echo "→ Subindo containers..."
	docker compose up -d --build
	@echo "  ✓ Containers iniciados"

.PHONY: reset
reset: teardown setup

.PHONY: teardown
teardown:
	@echo "→ Removendo containers, volumes e imagens..."
	docker compose down -v --rmi local
	@echo "  ✓ Ambiente removido"

# ── Airflow ───────────────────────────────────────────────────────────────────

.PHONY: wait-airflow
wait-airflow:
	@echo "→ Aguardando Airflow..."
	@timeout=120; \
	while [ $$timeout -gt 0 ]; do \
		status=$$(curl -s -o /dev/null -w "%{http_code}" $(AIRFLOW_URL)/health); \
		if [ "$$status" = "200" ]; then \
			echo "  ✓ Airflow pronto"; \
			exit 0; \
		fi; \
		sleep 5; \
		timeout=$$((timeout - 5)); \
	done; \
	echo "  ✗ Airflow não respondeu. Verifique: docker compose logs airflow-webserver"; \
	exit 1

.PHONY: trigger-pipeline
trigger-pipeline:
	@echo "→ Ativando e disparando o pipeline..."
	@unpause=$$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
		"$(AIRFLOW_URL)/api/v1/dags/$(DAG_ID)" \
		-H "Content-Type: application/json" \
		-u "$(AIRFLOW_USER):$(AIRFLOW_PASS)" \
		-d '{"is_paused": false}'); \
	if [ "$$unpause" != "200" ]; then \
		echo "  ✗ Não foi possível ativar o DAG (HTTP $$unpause). Verifique se o Airflow subiu corretamente."; \
		exit 1; \
	fi
	@run_id=$$(curl -s -X POST "$(AIRFLOW_URL)/api/v1/dags/$(DAG_ID)/dagRuns" \
		-H "Content-Type: application/json" \
		-u "$(AIRFLOW_USER):$(AIRFLOW_PASS)" \
		-d '{"conf": {}}' \
		| python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dag_run_id','?'))"); \
	echo "  ✓ Pipeline iniciado (run: $$run_id)"

.PHONY: wait-pipeline
wait-pipeline:
	@echo "→ Aguardando pipeline (ingest → dbt run → dbt test → export_last_month)..."
	@elapsed=0; \
	while true; do \
		response=$$(curl -s -u "$(AIRFLOW_USER):$(AIRFLOW_PASS)" \
			"$(AIRFLOW_URL)/api/v1/dags/$(DAG_ID)/dagRuns?order_by=-start_date&limit=1"); \
		state=$$(echo "$$response" | python3 -c \
			"import sys,json; runs=json.load(sys.stdin).get('dag_runs',[]); print(runs[0]['state'] if runs else 'queued')" 2>/dev/null); \
		tasks=$$(docker compose exec -T airflow-webserver \
			airflow tasks list $(DAG_ID) 2>/dev/null | tr '\n' ' '); \
		running_task=$$(docker compose exec -T airflow-webserver \
			airflow tasks states-for-dag-run $(DAG_ID) \
			$$(echo "$$response" | python3 -c "import sys,json; runs=json.load(sys.stdin).get('dag_runs',[]); print(runs[0]['run_id'] if runs else '')" 2>/dev/null) \
			2>/dev/null | grep "running\|queued" | awk '{print $$1}' | head -1); \
		if [ -n "$$running_task" ]; then \
			detail=" — tarefa: $$running_task"; \
		else \
			detail=""; \
		fi; \
		echo "  [$$elapsed s] $$state$$detail"; \
		if [ "$$state" = "success" ]; then \
			echo "  ✓ Pipeline concluído com sucesso ($$elapsed s)"; \
			exit 0; \
		elif [ "$$state" = "failed" ]; then \
			echo "  ✗ Pipeline falhou. Logs: make logs-pipeline"; \
			exit 1; \
		fi; \
		sleep 15; \
		elapsed=$$((elapsed + 15)); \
		if [ $$elapsed -ge 900 ]; then \
			echo "  ✗ Timeout (900s). Verifique: $(AIRFLOW_URL)"; \
			exit 1; \
		fi; \
	done

# ── Utilitários ───────────────────────────────────────────────────────────────

.PHONY: open
open:
	open $(AIRFLOW_URL)  || xdg-open $(AIRFLOW_URL)  2>/dev/null || true
	open $(SUPERSET_URL) || xdg-open $(SUPERSET_URL) 2>/dev/null || true

.PHONY: logs-bootstrap
logs-bootstrap:
	docker compose logs -f superset-bootstrap

.PHONY: logs-pipeline
logs-pipeline:
	docker compose exec -T airflow-webserver \
		airflow tasks logs $(DAG_ID) \
		$$(docker compose exec -T airflow-webserver \
			airflow dags list-runs --dag-id $(DAG_ID) -o plain 2>/dev/null \
			| awk 'NR==2{print $$3}') \
		--all 2>/dev/null || docker compose logs airflow-webserver | tail -50

.PHONY: status
status:
	@echo "── Containers ──"
	@docker compose ps --format "table {{.Name}}\t{{.Status}}"
	@echo ""
	@echo "── Último run do pipeline ──"
	@curl -s -u "$(AIRFLOW_USER):$(AIRFLOW_PASS)" \
		"$(AIRFLOW_URL)/api/v1/dags/$(DAG_ID)/dagRuns?order_by=-start_date&limit=1" \
		| python3 -c "import sys,json; runs=json.load(sys.stdin).get('dag_runs',[]); r=runs[0] if runs else {}; print(f\"  estado : {r.get('state','nenhum run')}\n  início : {r.get('start_date','-')}\n  fim    : {r.get('end_date','-')}\")" 2>/dev/null
