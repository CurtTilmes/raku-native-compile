CWD := $(shell pwd)
NAME := $(shell jq -r .name META6.json)
VERSION := $(shell jq -r .version META6.json)
ARCHIVENAME := $(subst ::,-,$(NAME))

check:
	git diff-index --check HEAD
	prove6

tag:
	git tag $(VERSION)
	git push origin --tags

dist:
	git archive --prefix=$(ARCHIVENAME)-$(VERSION)/ \
		-o ../$(ARCHIVENAME)-$(VERSION).tar.gz $(VERSION)

README.md: lib/Native/Compile.rakumod
	raku --doc $< > $@

test:
	docker run --rm -t \
	  -e ALL_TESTING=1 \
	  -v $(CWD):/tmp/test -w /tmp/test \
	  tonyodell/rakudo-nightly:latest \
	  bash -c 'apt install -y libssl-dev && zef install --/test --deps-only --test-depends . && zef -v test .'
