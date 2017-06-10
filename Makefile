SASSDIR=sass
CSSDIR=public/css

${CSSDIR}/main.css: $(wildcard ${SASSDIR}/*.scss)
	sass --style=compressed --compass --sourcemap=none ${SASSDIR}/main.scss $@

.PHONY: clear
clear:
	rm ${CSSDIR}/main.css

