SHELL := /bin/bash
DC := docker compose
N8N := $(DC) exec -T n8n n8n
PSQL := $(DC) exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" "$$@"' --
# idempotency_key of fixtures/zoom/recording.completed.json (<meeting_uuid>:<audio file_id>)
FIXTURE_KEY := 4444AAAiAAAAAiAiAiiAii==:a1b2c3d4-0000-1111-2222-333344445555
LAST_EXEC_SQL := select e.id || '|' || e.status || '|' || d.data from execution_entity e join execution_data d on d.\"executionId\" = e.id order by e.id desc limit 1

.PHONY: help init up down logs tunnel tunnel-url import export publish test-webhook ps db-migrate db-shell test-idempotency test-mock-zoom last-execution test-download test-transcribe test-analyze

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-18s %s\n",$$1,$$2}'

init: ## Create .env with generated secrets
	@test -f .env && echo ".env exists" || ( cp .env.example .env && \
	  sed -i "s|^N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=$$(openssl rand -hex 32)|; \
	          s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$$(openssl rand -hex 16)|" .env && echo ".env created" )

up: ## Start postgres + n8n
	$(DC) up -d --wait

down: ## Stop stack
	$(DC) --profile tunnel down

ps: ## Stack status
	$(DC) --profile tunnel ps

logs: ## Tail n8n logs
	$(DC) logs -f n8n

tunnel: ## Start Cloudflare quick tunnel and print public URL
	$(DC) --profile tunnel up -d tunnel
	@$(MAKE) -s tunnel-url

tunnel-url: ## Print tunnel URL
	@for i in $$(seq 1 20); do \
	  url=$$($(DC) logs tunnel 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1); \
	  [ -n "$$url" ] && { echo "$$url/webhook/zoom"; exit 0; }; sleep 1; done; echo "tunnel URL not found"; exit 1

import: ## Import workflows/*.json into n8n
	$(N8N) import:workflow --separate --input=/workflows/

export: ## Export all workflows to workflows/ (commit these)
	$(N8N) export:workflow --backup --output=/workflows/
	python3 scripts/clean_workflow_exports.py workflows/*.json

publish: ## Publish (activate) workflow: make publish ID=zoomIntake00001
	$(N8N) publish:workflow --id=$(ID)
	$(DC) restart n8n && $(DC) up -d --wait n8n

test-webhook: ## Send signed fixtures to local webhook
	./scripts/send_zoom_event.py fixtures/zoom/endpoint.url_validation.json
	./scripts/send_zoom_event.py fixtures/zoom/recording.completed.json
	./scripts/send_zoom_event.py fixtures/zoom/recording.completed.json --bad-signature

last-execution: ## Summary of the latest n8n execution (no item data)
	@$(PSQL) -Atc "$(LAST_EXEC_SQL)" | python3 scripts/last_execution.py

test-download: ## Fresh recording.completed → n8n downloads audio from mock-zoom
	@$(PSQL) -qc "delete from app.processed_events where idempotency_key='$(FIXTURE_KEY)'"
	./scripts/send_zoom_event.py fixtures/zoom/recording.completed.json
	@sleep 5; $(PSQL) -Atc "$(LAST_EXEC_SQL)" | python3 scripts/last_execution.py --expect-node "Download Audio"

test-transcribe: ## Fresh event → download → Whisper; prints text length only (~$0.006/min audio)
	@$(PSQL) -qc "delete from app.processed_events where idempotency_key='$(FIXTURE_KEY)'"
	./scripts/send_zoom_event.py fixtures/zoom/recording.completed.json
	@echo "waiting for transcription..."; for i in $$(seq 1 60); do sleep 3; \
	  st=$$($(PSQL) -Atc "select status from execution_entity order by id desc limit 1"); \
	  [ "$$st" != "running" ] && [ "$$st" != "new" ] && break; done
	@$(PSQL) -Atc "$(LAST_EXEC_SQL)" | python3 scripts/last_execution.py --expect-node "Transcribe" --text-stats "Transcribe"

test-analyze: ## Fresh event → … → Transcribe → Analyze; prints output structure only
	@$(PSQL) -qc "delete from app.processed_events where idempotency_key='$(FIXTURE_KEY)'"
	./scripts/send_zoom_event.py fixtures/zoom/recording.completed.json
	@echo "waiting for pipeline..."; for i in $$(seq 1 80); do sleep 3; \
	  st=$$($(PSQL) -Atc "select status from execution_entity order by id desc limit 1"); \
	  [ "$$st" != "running" ] && [ "$$st" != "new" ] && break; done
	@$(PSQL) -Atc "$(LAST_EXEC_SQL)" | python3 scripts/last_execution.py --expect-node "Analyze" --shape "Analyze"

test-mock-zoom: ## Check n8n can download fixtures/audio/sample.m4a from mock-zoom
	@test -f fixtures/audio/sample.m4a || { echo "missing fixtures/audio/sample.m4a (see fixtures/audio/README.md)"; exit 1; }
	@size=$$($(DC) exec -T n8n sh -c 'wget -qO- http://mock-zoom:8000/sample.m4a | wc -c'); \
	  expected=$$(stat -c %s fixtures/audio/sample.m4a); \
	  echo "downloaded $$size bytes, expected $$expected"; [ "$$size" = "$$expected" ] && echo "mock-zoom OK" || { echo "mock-zoom FAILED"; exit 1; }

db-migrate: ## Apply db/migrations/*.sql (idempotent)
	@for f in db/migrations/*.sql; do echo "→ $$f"; $(PSQL) -q < $$f || exit 1; done

db-shell: ## Open psql
	$(DC) exec postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'

test-idempotency: ## Send the same recording.completed twice → exactly one row
	@$(PSQL) -qc "delete from app.processed_events where idempotency_key='$(FIXTURE_KEY)'"
	./scripts/send_zoom_event.py fixtures/zoom/recording.completed.json
	./scripts/send_zoom_event.py fixtures/zoom/recording.completed.json
	@sleep 3; n=$$($(PSQL) -Atc "select count(*) from app.processed_events where idempotency_key='$(FIXTURE_KEY)'"); \
	  echo "rows for fixture key: $$n"; [ "$$n" = "1" ] || { echo "idempotency FAILED (expected 1)"; exit 1; }
	@bad=$$($(PSQL) -Atc "select count(*) from (select status from execution_entity order by id desc limit 2) s where status <> 'success'"); \
	  [ "$$bad" = "0" ] && echo "idempotency OK (2 executions succeeded)" || { echo "FAILED: $$bad of last 2 executions not successful — see n8n → Executions"; exit 1; }
