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
	@echo "  Loadsmart Case — available commands"
	@echo ""
	@echo "  make setup          Full stack from scratch (Docker → pipeline → Superset)"
	@echo "  make reset          Tear down and rebuild from scratch (teardown + setup)"
	@echo "  make up             Start containers"
	@echo "  make pipeline       Run the data pipeline in Airflow"
	@echo "  make status         Show container status and last pipeline run"
	@echo "  make teardown       Stop and remove containers, volumes, and images"
	@echo "  make open           Open Airflow and Superset in the browser"
	@echo "  make logs-pipeline  Data pipeline logs"
	@echo "  make logs-bootstrap Superset setup logs"
	@echo ""

# ── Full setup ────────────────────────────────────────────────────────────────

.PHONY: setup
setup: up wait-airflow trigger-pipeline wait-pipeline
	@echo ""
	@echo "  ✓ Pipeline finished. Superset is configuring dashboards..."
	@echo ""
	@echo "  → Superset : http://localhost:8088 (admin / admin)"
	@echo "  → Airflow  : http://localhost:9090 (admin / admin)"
	@echo ""

# ── Docker ────────────────────────────────────────────────────────────────────

.PHONY: up
up:
	@echo "→ Starting containers..."
	docker compose up -d --build
	@echo "  ✓ Containers started"

.PHONY: reset
reset: teardown setup

.PHONY: teardown
teardown:
	@echo "→ Removing containers, volumes, and images..."
	docker compose down -v --rmi local
	@echo "  ✓ Environment removed"

# ── Airflow ───────────────────────────────────────────────────────────────────

.PHONY: wait-airflow
wait-airflow:
	@echo "→ Waiting for Airflow..."
	@timeout=120; \
	while [ $$timeout -gt 0 ]; do \
		status=$$(curl -s -o /dev/null -w "%{http_code}" $(AIRFLOW_URL)/health); \
		if [ "$$status" = "200" ]; then \
			echo "  ✓ Airflow ready"; \
			exit 0; \
		fi; \
		sleep 5; \
		timeout=$$((timeout - 5)); \
	done; \
	echo "  ✗ Airflow did not respond. Check: docker compose logs airflow-webserver"; \
	exit 1

.PHONY: trigger-pipeline
trigger-pipeline:
	@echo "→ Enabling and triggering pipeline..."
	@unpause=$$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
		"$(AIRFLOW_URL)/api/v1/dags/$(DAG_ID)" \
		-H "Content-Type: application/json" \
		-u "$(AIRFLOW_USER):$(AIRFLOW_PASS)" \
		-d '{"is_paused": false}'); \
	if [ "$$unpause" != "200" ]; then \
		echo "  ✗ Could not enable DAG (HTTP $$unpause). Check that Airflow started correctly."; \
		exit 1; \
	fi
	@run_id=$$(curl -s -X POST "$(AIRFLOW_URL)/api/v1/dags/$(DAG_ID)/dagRuns" \
		-H "Content-Type: application/json" \
		-u "$(AIRFLOW_USER):$(AIRFLOW_PASS)" \
		-d '{"conf": {}}' \
		| python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dag_run_id','?'))"); \
	echo "  ✓ Pipeline started (run: $$run_id)"

.PHONY: wait-pipeline
wait-pipeline:
	@echo "→ Waiting for pipeline (ingest → dbt deps → dbt run → dbt test → export_last_month)..."
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
			detail=" — task: $$running_task"; \
		else \
			detail=""; \
		fi; \
		echo "  [$$elapsed s] $$state$$detail"; \
		if [ "$$state" = "success" ]; then \
			echo "  ✓ Pipeline completed successfully ($$elapsed s)"; \
			latest_csv=$$(ls -t data/exports/*.csv 2>/dev/null | head -1); \
			if [ -n "$$latest_csv" ]; then \
				echo "  ✓ CSV exported: $$latest_csv"; \
			fi; \
			smtp_user=$$(grep -E '^SMTP_USER=.+' .env 2>/dev/null | cut -d= -f2-); \
			smtp_pass=$$(grep -E '^SMTP_PASSWORD=.+' .env 2>/dev/null | cut -d= -f2-); \
			smtp_recip=$$(grep -E '^SMTP_RECIPIENTS=.+' .env 2>/dev/null | cut -d= -f2-); \
			if [ -n "$$smtp_user" ] && [ -n "$$smtp_pass" ] && [ -n "$$smtp_recip" ]; then \
				echo "  ✓ Email sent to: $$smtp_recip"; \
			fi; \
			exit 0; \
		elif [ "$$state" = "failed" ]; then \
			echo "  ✗ Pipeline failed. Logs: make logs-pipeline"; \
			exit 1; \
		fi; \
		sleep 15; \
		elapsed=$$((elapsed + 15)); \
		if [ $$elapsed -ge 900 ]; then \
			echo "  ✗ Timeout (900s). Check: $(AIRFLOW_URL)"; \
			exit 1; \
		fi; \
	done

# ── Utilities ───────────────────────────────────────────────────────────────

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
	@echo "── Last pipeline run ──"
	@curl -s -u "$(AIRFLOW_USER):$(AIRFLOW_PASS)" \
		"$(AIRFLOW_URL)/api/v1/dags/$(DAG_ID)/dagRuns?order_by=-start_date&limit=1" \
		| python3 -c "import sys,json; runs=json.load(sys.stdin).get('dag_runs',[]); r=runs[0] if runs else {}; print(f\"  state  : {r.get('state','no run')}\n  start  : {r.get('start_date','-')}\n  end    : {r.get('end_date','-')}\")" 2>/dev/null
