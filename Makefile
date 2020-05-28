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

test-alpine:
	docker run --rm -t  \
	  -e ALL_TESTING=1 \
	  -v $(CWD):/test \
          --entrypoint="/bin/sh" \
	  jjmerelo/raku-test \
	  -c "apk add --update --no-cache gcc g++ openssl-dev && zef install --/test --deps-only --test-depends . && zef -v test ."

test-debian:
	docker run --rm -t \
	  -e ALL_TESTING=1 \
	  -v $(CWD):/test -w /test \
          --entrypoint="/bin/sh" \
	  jjmerelo/rakudo-nostar \
	  -c "echo deb http://ftp.us.debian.org/debian testing main contrib non-free >> /etc/apt/sources.list && apt update && apt install -y gcc g++ && zef install --/test --deps-only --test-depends . && zef -v test ."

test-centos:
	docker run --rm -t \
	  -e ALL_TESTING=1 \
	  -v $(CWD):/test -w /test \
          --entrypoint="/bin/bash" \
	  centos:latest \
	  -c "yum install -y gcc gcc-c++ wget curl git openssl-devel && wget https://dl.bintray.com/nxadm/rakudo-pkg-rpms/CentOS/8/x86_64/rakudo-pkg-CentOS8-2020.02.1-04.x86_64.rpm && yum install -y rakudo-pkg-CentOS8-2020.02.1-04.x86_64.rpm && rm rakudo-pkg-CentOS8-2020.02.1-04.x86_64.rpm && source ~/.bashrc && zef install --/test --deps-only --test-depends . && zef -v test ."

test: test-alpine test-debian test-centos
