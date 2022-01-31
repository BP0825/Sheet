SHELL=/bin/bash
LIB=xlsx
FMT=xlsx xlsm xlsb ods xls xml misc full
REQS=jszip.js
ADDONS=dist/cpexcel.js
AUXTARGETS=
CMDS=bin/xlsx.njs
HTMLLINT=index.html

MINITGT=xlsx.mini.js
MINIFLOW=xlsx.mini.flow.js
MINIDEPS=$(shell cat mini.lst)

NODESMTGT=xlsx.esm.mjs
NODESMDEPS=$(shell cat misc/esm.lst)
ESMJSTGT=xlsx.mjs
ESMJSDEPS=$(shell cat misc/mjs.lst)


ULIB=$(shell echo $(LIB) | tr a-z A-Z)
DEPS=$(sort $(wildcard bits/*.js))
TARGET=$(LIB).js
FLOWTARGET=$(LIB).flow.js
FLOWAUX=$(patsubst %.js,%.flow.js,$(AUXTARGETS))
AUXSCPTS=xlsxworker.js
FLOWTGTS=$(TARGET) $(AUXTARGETS) $(AUXSCPTS) $(MINITGT)
UGLIFYOPTS=--support-ie8 -m
CLOSURE=/usr/local/lib/node_modules/google-closure-compiler/compiler.jar

## Main Targets

.PHONY: all
all: $(TARGET) $(AUXTARGETS) $(AUXSCPTS) $(MINITGT) $(NODESMTGT) $(ESMJSTGT) ## Build library and auxiliary scripts

$(FLOWTGTS): %.js : %.flow.js
	node -e 'process.stdout.write(require("fs").readFileSync("$<","utf8").replace(/^[ \t]*\/\*[:#][^*]*\*\/\s*(\n)?/gm,"").replace(/\/\*[:#][^*]*\*\//gm,""))' > $@

$(FLOWTARGET): $(DEPS)
	cat $^ | tr -d '\15\32' > $@

$(MINIFLOW): $(MINIDEPS)
	cat $^ | tr -d '\15\32' > $@

$(NODESMTGT): $(NODESMDEPS)
	cat $^ | tr -d '\15\32' > $@

$(ESMJSTGT): $(ESMJSDEPS)
	cat $^ | tr -d '\15\32' > $@

bits/01_version.js: package.json
	echo "$(ULIB).version = '"`grep version package.json | awk '{gsub(/[^0-9a-z\.-]/,"",$$2); print $$2}'`"';" > $@

bits/18_cfb.js: node_modules/cfb/xlscfb.flow.js
	cp $^ $@

bits/83_numbers.js: modules/83_numbers.js
	cp $^ $@


.PHONY: clean
clean: ## Remove targets and build artifacts
	rm -f $(TARGET) $(FLOWTARGET)

.PHONY: clean-data
clean-data:
	rm -f *.xlsx *.xlsm *.xlsb *.xls *.xml

.PHONY: init
init: ## Initial setup for development
	git submodule init
	git submodule update
	#git submodule foreach git pull origin master
	git submodule foreach make
	mkdir -p tmp

DISTHDR=misc/suppress_export.js
.PHONY: dist
dist: dist-deps $(TARGET) bower.json ## Prepare JS files for distribution
	mkdir -p dist
	<$(TARGET) sed "s/require('....*')/undefined/g" > dist/$(TARGET)
	cp LICENSE dist/
	uglifyjs shim.js $(UGLIFYOPTS) -o dist/shim.min.js --preamble "$$(head -n 1 bits/00_header.js)"
	uglifyjs $(DISTHDR) dist/$(TARGET) $(UGLIFYOPTS) -o dist/$(LIB).min.js --source-map dist/$(LIB).min.map --preamble "$$(head -n 1 bits/00_header.js)"
	misc/strip_sourcemap.sh dist/$(LIB).min.js
	uglifyjs $(DISTHDR) $(REQS) dist/$(TARGET) $(UGLIFYOPTS) -o dist/$(LIB).core.min.js --source-map dist/$(LIB).core.min.map --preamble "$$(head -n 1 bits/00_header.js)"
	misc/strip_sourcemap.sh dist/$(LIB).core.min.js
	uglifyjs $(DISTHDR) $(REQS) $(ADDONS) dist/$(TARGET) $(AUXTARGETS) $(UGLIFYOPTS) -o dist/$(LIB).full.min.js --source-map dist/$(LIB).full.min.map --preamble "$$(head -n 1 bits/00_header.js)"
	uglifyjs $(DISTHDR) $(MINITGT) $(UGLIFYOPTS) -o dist/$(LIB).mini.min.js --source-map dist/$(LIB).mini.min.map --preamble "$$(head -n 1 bits/00_header.js)"
	misc/strip_sourcemap.sh dist/$(LIB).full.min.js
	misc/strip_sourcemap.sh dist/$(LIB).mini.min.js
	cat <(head -n 1 bits/00_header.js) shim.js $(DISTHDR) $(REQS) dist/$(TARGET) > dist/$(LIB).extendscript.js

.PHONY: dist-deps
dist-deps: ## Copy dependencies for distribution
	mkdir -p dist
	cp node_modules/codepage/dist/cpexcel.full.js dist/cpexcel.js

.PHONY: aux
aux: $(AUXTARGETS)

BYTEFILE=dist/xlsx.min.js dist/xlsx.{core,full,mini}.min.js dist/xlsx.extendscript.js
.PHONY: bytes
bytes: ## Display minified and gzipped file sizes
	for i in $(BYTEFILE); do printj "%-30s %7d %10d" $$i $$(wc -c < $$i) $$(gzip --best --stdout $$i | wc -c); done

.PHONY: graph
graph: formats.png legend.png ## Rebuild format conversion graph
misc/formats.svg: misc/formats.dot
	circo -Tsvg -o$@ $<
misc/legend.svg: misc/legend.dot
	dot -Tsvg -o$@ $<
formats.png legend.png: %.png: misc/%.svg
	node misc/coarsify.js misc/$*.svg misc/$*.svg.svg
	npx svgexport misc/$*.svg.svg $@ 0.5x


.PHONY: nexe
nexe: xlsx.exe ## Build nexe standalone executable

xlsx.exe: bin/xlsx.njs xlsx.js
	tail -n+2 $< | sed 's#\.\./#./xlsx#g' > nexe.js
	nexe -i nexe.js -o $@
	rm nexe.js

.PHONY: pkg
pkg: bin/xlsx.njs xlsx.js ## Build pkg standalone executable
	pkg $<

## Testing

.PHONY: test mocha
test mocha: test.js ## Run test suite
	mocha -R spec -t 30000

#*                      To run tests for one format, make test_<fmt>
#*                      To run the core test suite, make test_misc
TESTFMT=$(patsubst %,test_%,$(FMT))
.PHONY: $(TESTFMT)
$(TESTFMT): test_%:
	FMTS=$* make test

.PHONY: travis
travis: ## Run test suite with minimal output
	mocha -R dot -t 30000

.PHONY: ctest
ctest: ## Build browser test fixtures
	node tests/make_fixtures.js

.PHONY: ctestserv
ctestserv: ## Start a test server on port 8000
	@cd tests && python -mSimpleHTTPServer

## Code Checking

.PHONY: fullint
fullint: lint mdlint ## Run all checks (removed: old-lint, tslint, flow)

.PHONY: lint
lint: $(TARGET) $(AUXTARGETS) ## Run eslint checks
	@./node_modules/.bin/eslint --ext .js,.njs,.json,.html,.htm $(TARGET) $(AUXTARGETS) $(CMDS) $(HTMLLINT) package.json bower.json
	@if [ -x "$(CLOSURE)" ]; then java -jar $(CLOSURE) $(REQS) $(FLOWTARGET) --jscomp_warning=reportUnknownTypes >/dev/null; fi

.PHONY: old-lint
old-lint: $(TARGET) $(AUXTARGETS) ## Run jshint and jscs checks
	@./node_modules/.bin/jshint --show-non-errors $(TARGET) $(AUXTARGETS)
	@./node_modules/.bin/jshint --show-non-errors $(CMDS)
	@./node_modules/.bin/jshint --show-non-errors package.json bower.json test.js
	@./node_modules/.bin/jshint --show-non-errors --extract=always $(HTMLLINT)
	@./node_modules/.bin/jscs $(TARGET) $(AUXTARGETS) test.js
	@if [ -x "$(CLOSURE)" ]; then java -jar $(CLOSURE) $(REQS) $(FLOWTARGET) --jscomp_warning=reportUnknownTypes >/dev/null; fi

.PHONY: tslint
tslint: $(TARGET) ## Run typescript checks
	#@npm install dtslint typescript
	#@npm run-script dtslint
	./node_modules/.bin/dtslint types

.PHONY: flow
flow: lint ## Run flow checker
	@./node_modules/.bin/flow check --all --show-all-errors --include-warnings

.PHONY: cov
cov: misc/coverage.html ## Run coverage test

#*                      To run coverage tests for one format, make cov_<fmt>
COVFMT=$(patsubst %,cov_%,$(FMT))
.PHONY: $(COVFMT)
$(COVFMT): cov_%:
	FMTS=$* make cov

misc/coverage.html: $(TARGET) test.js
	mocha --require blanket -R html-cov -t 30000 > $@

.PHONY: coveralls
coveralls: ## Coverage Test + Send to coveralls.io
	mocha --require blanket --reporter mocha-lcov-reporter -t 30000 | node ./node_modules/coveralls/bin/coveralls.js

READEPS=$(sort $(wildcard docbits/*.md))
README.md: $(READEPS)
	awk 'FNR==1{p=0}/#/{p=1}p' $^ | tr -d '\15\32' > $@

.PHONY: readme
readme: README.md ## Update README Table of Contents
	markdown-toc -i README.md

.PHONY: book
book: readme graph ## Update summary for documentation
	printf "# Summary\n\n- [xlsx](README.md#sheetjs-js-xlsx)\n" > misc/docs/SUMMARY.md
	markdown-toc README.md | sed 's/(#/(README.md#/g'>> misc/docs/SUMMARY.md
	<README.md grep -vE "(details|summary)>" > misc/docs/README.md

DEMOMDS=$(sort $(wildcard demos/*/README.md))
MDLINT=$(DEMOMDS) $(READEPS) demos/README.md
.PHONY: mdlint
mdlint: $(MDLINT) ## Check markdown documents
	./node_modules/.bin/alex $^
	./node_modules/.bin/mdspell -a -n -x -r --en-us $^

.PHONY: help
help:
	@grep -hE '(^[a-zA-Z_-][ a-zA-Z_-]*:.*?|^#[#*])' $(MAKEFILE_LIST) | bash misc/help.sh

#* To show a spinner, append "-spin" to any target e.g. cov-spin
%-spin:
	@make $* & bash misc/spin.sh $$!
