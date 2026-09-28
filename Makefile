SHELL := /bin/bash
DC := docker compose
N8N := $(DC) exec -T n8n n8n

.PHONY: help init up down logs tunnel tunnel-url import export publish test-webhook ps

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-14s %s\n",$$1,$$2}'

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

publish: ## Publish (activate) workflow: make publish ID=zoomIntake00001
	$(N8N) publish:workflow --id=$(ID)
	$(DC) restart n8n && $(DC) up -d --wait n8n

test-webhook: ## Send signed fixtures to local webhook
	./scripts/send_zoom_event.py fixtures/zoom/endpoint.url_validation.json
	./scripts/send_zoom_event.py fixtures/zoom/recording.completed.json
	./scripts/send_zoom_event.py fixtures/zoom/recording.completed.json --bad-signature
