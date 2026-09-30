BOLD  := \033[1m
CYAN  := \033[36m
GREEN := \033[32m
RESET := \033[0m

.DEFAULT_GOAL := help

# ── Quality ──────────────────────────────────────────────────────────────────

.PHONY: audit test

audit: ## Check required tools and run shellcheck and repository audits
	scripts/audit.sh

test: ## Run unit tests
	python3 -m unittest discover -s tests

# ── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "\n$(BOLD)codex-agents-local$(RESET) — local-only AGENTS.local.md instructions for Codex\n"} \
		/^# ── / {n = $$0; gsub(/(^# ── | (─)+$$)/, "", n); printf "\n$(BOLD)%s$(RESET)\n", n} \
		/^[a-zA-Z0-9_-]+:.*## / {printf "  $(CYAN)make %-10s$(RESET) %s\n", $$1, $$2} \
		END {printf "\n"}' $(MAKEFILE_LIST)
