# Development checks for this toolkit. Requires Docker only.
SCRIPTS := dock configure-app.sh $(wildcard scripts/lib/*.sh)

.PHONY: lint shellcheck syntax compose

lint: syntax shellcheck compose

syntax:
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done
	@echo "bash -n: ok"

shellcheck:
	@docker run --rm -v "$(CURDIR):/mnt" -w /mnt koalaman/shellcheck:stable $(SCRIPTS)
	@echo "shellcheck: ok"

compose:
	@scripts/dev/check-compose.sh
