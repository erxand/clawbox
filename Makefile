.PHONY: start stop status logs shell tui chat backup restore upgrade build-airgap test-isolation clean install help

COMPOSE := docker compose
CONTAINER := clawbox-work
VOLUME := clawbox_clawbox-work-state
BACKUP_DIR := backups
GATEWAY_URL := ws://localhost:18790
# Token value doesn't matter (gateway runs auth=none) but the CLI
# requires something to be set when using a URL override.
GATEWAY_TOKEN := clawbox

install: ## Install clawbox CLI to /usr/local/bin (run once after cloning)
	@chmod +x clawbox
	@sudo cp clawbox /usr/local/bin/clawbox
	@sudo sed -i '' "s|CLAWBOX_DIR:-\$$SCRIPT_DIR|CLAWBOX_DIR:-$(shell pwd)|g" /usr/local/bin/clawbox 2>/dev/null || true
	@echo "✓ clawbox installed. Run: clawbox help"

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

start: ## Start the container
	$(COMPOSE) up -d
	@echo "Waiting for healthy..."
	@for i in $$(seq 1 30); do \
		STATUS=$$(docker inspect $(CONTAINER) --format '{{.State.Health.Status}}' 2>/dev/null); \
		if [ "$$STATUS" = "healthy" ]; then echo "Container healthy."; break; fi; \
		sleep 3; \
	done

stop: ## Stop the container
	$(COMPOSE) down

status: ## Show container and gateway status
	@$(COMPOSE) ps
	@echo ""
	@$(COMPOSE) exec $(CONTAINER) openclaw gateway health 2>/dev/null || \
		echo "Gateway not reachable (container may be starting)"

logs: ## Tail container logs
	$(COMPOSE) logs -f

shell: ## Shell into the running container
	$(COMPOSE) exec $(CONTAINER) sh

tui: ## Open interactive TUI chat session with the container agent
	OPENCLAW_GATEWAY_URL=$(GATEWAY_URL) OPENCLAW_GATEWAY_TOKEN=$(GATEWAY_TOKEN) openclaw tui

chat: tui ## Alias for 'make tui'

backup: ## Backup volume to tar.gz
	@mkdir -p $(BACKUP_DIR)
	@BACKUP_FILE=$(BACKUP_DIR)/$(VOLUME)-$$(date +%Y%m%d-%H%M%S).tar.gz; \
	echo "Backing up volume to $$BACKUP_FILE..."; \
	docker run --rm \
		-v $(VOLUME):/data:ro \
		-v $$(pwd)/$(BACKUP_DIR):/backup \
		alpine tar czf /backup/$$(basename $$BACKUP_FILE) -C /data . && \
	echo "Done: $$BACKUP_FILE"

restore: ## Restore from tar.gz (usage: make restore FILE=path/to/backup.tar.gz)
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make restore FILE=backups/your-backup.tar.gz"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "File not found: $(FILE)"; \
		exit 1; \
	fi
	@echo "Restoring from $(FILE)..."
	@$(COMPOSE) down 2>/dev/null || true
	docker run --rm \
		-v $(VOLUME):/data \
		-v $$(pwd)/$(FILE):/backup.tar.gz:ro \
		alpine sh -c "rm -rf /data/* && tar xzf /backup.tar.gz -C /data"
	@echo "Restored. Run 'make start' to start the container."

upgrade: ## Rebuild image with latest openclaw and restart
	$(COMPOSE) down
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d
	@echo "Upgraded. Waiting for healthy..."
	@for i in $$(seq 1 30); do \
		STATUS=$$(docker inspect $(CONTAINER) --format '{{.State.Health.Status}}' 2>/dev/null); \
		if [ "$$STATUS" = "healthy" ]; then echo "Container healthy. Run 'make status' to verify."; break; fi; \
		sleep 3; \
	done

build-airgap: ## Build the air-gapped image (downloads docs + npm cache)
	$(COMPOSE) build --no-cache

test-isolation: ## Verify network isolation is working
	@echo "Testing that container cannot reach internet..."
	@docker exec $(CONTAINER) sh -c "curl -s --max-time 5 https://example.com" && echo "FAIL: internet accessible" || echo "PASS: internet blocked"
	@echo "Testing that Anthropic API is reachable via proxy..."
	@OPENCLAW_GATEWAY_URL=$(GATEWAY_URL) OPENCLAW_GATEWAY_TOKEN=$(GATEWAY_TOKEN) openclaw gateway health && echo "PASS: gateway healthy" || echo "FAIL: gateway unreachable"

clean: ## Stop container and remove volume (destructive! FORCE=1 skips confirmation)
	@if [ "$(FORCE)" = "1" ]; then \
		$(COMPOSE) down -v; \
		echo "Cleaned."; \
	else \
		echo "This will STOP the container and DELETE all OpenClaw data."; \
		read -p "Are you sure? [y/N] " confirm; \
		if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
			$(COMPOSE) down -v; \
			echo "Cleaned."; \
		else \
			echo "Aborted."; \
		fi; \
	fi
