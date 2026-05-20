.PHONY: audit test

audit:
	scripts/audit.sh

test:
	python3 -m unittest discover -s tests
