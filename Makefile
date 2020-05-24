#
# http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
#

.PHONY: help

.DEFAULT_GOAL := help

help:
	@echo "Please use \`make <target>' where <target> is one of"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

init: venv ## Initialize the project

venv: venv/bin/activate ## Initialize venv

venv/bin/activate:
	test -d venv || virtualenv -p /usr/local/bin/python3 venv
	. venv/bin/activate; pip install -e .; which amify
	touch venv/bin/activate
