SASSDIR=sass
CSSDIR=public/css
BASEURL ?= https://www.0value.com

${CSSDIR}/main.css: $(wildcard ${SASSDIR}/*.scss)
	sass --style=compressed --compass --sourcemap=none ${SASSDIR}/main.scss $@

.PHONY: generate
generate:
	trofaf -g -b ${BASEURL} -n "ø value" -t "a wysiwyg hypertext cyberblog"
	scripts/extensionify.sh

.PHONY: clear
clear:
	rm ${CSSDIR}/main.css

