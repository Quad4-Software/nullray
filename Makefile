ODIN   ?= odin
ROOT   := $(CURDIR)
OUT    := bin/nullray
PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
MANDIR := $(PREFIX)/share/man/man1
COMPDIR := $(PREFIX)/share/nullray/completions

ifeq ($(OS),Windows_NT)
  LINKER := -extra-linker-flags:"libcurl"
else ifeq ($(shell uname -s 2>/dev/null),Darwin)
  CURL_PREFIX := $(shell brew --prefix curl 2>/dev/null)
  ifneq ($(CURL_PREFIX),)
    LINKER := -extra-linker-flags:"-L$(CURL_PREFIX)/lib -lcurl"
  else
    LINKER := -extra-linker-flags:"-lcurl"
  endif
else
  LINKER := -extra-linker-flags:"-lcurl"
endif

COLLECTION := -collection:nullray=$(ROOT)/nullray
BUILD_DATE := $(shell date -u +%Y-%m-%d)
BUILD_TIME := $(shell date -u +%H:%M:%S)
DEFINES    := -define:NULLRAY_BUILD_DATE="$(BUILD_DATE)" -define:NULLRAY_BUILD_TIME="$(BUILD_TIME)"

.PHONY: all clean install uninstall run test selftest chat-smoke print-smoke coverage help completions man \
	appimage flatpak docker-build debug

TEST_SUITES := ui agent tools skills session store sandbox mcp provider app config subagent elevate
TEST_FLAGS  := $(COLLECTION) -define:ODIN_TEST_THREADS=1 -debug

all: $(OUT)

$(OUT): $(shell find cmd/nullray nullray -name '*.odin' 2>/dev/null)
	@mkdir -p bin
	$(ODIN) build $(ROOT)/cmd/nullray -out:$(OUT) $(COLLECTION) $(LINKER) $(DEFINES)

debug:
	@mkdir -p bin
	$(ODIN) build $(ROOT)/cmd/nullray -out:$(OUT) $(COLLECTION) $(LINKER) $(DEFINES) -debug
	@echo "built $(OUT) with -debug (richer crash backtraces)"

run: $(OUT)
	./$(OUT)

test:
	@for s in $(TEST_SUITES); do \
		$(ODIN) test $(ROOT)/nullray/$$s $(COLLECTION) -define:ODIN_TEST_THREADS=1 || exit 1; \
	done
	@$(MAKE) --no-print-directory selftest
	@$(MAKE) --no-print-directory chat-smoke
	@$(MAKE) --no-print-directory print-smoke

# Local HTML coverage via kcov (Linux). Does not upload or gate CI.
coverage:
	@command -v kcov >/dev/null || { echo 'coverage: install kcov first'; exit 1; }
	@mkdir -p bin coverage
	@rm -rf coverage/raw-* coverage/html
	@mkdir -p coverage/html
	@for s in $(TEST_SUITES); do \
		echo "coverage: $$s"; \
		$(ODIN) test $(ROOT)/nullray/$$s $(TEST_FLAGS) -out:bin/test_$$s -keep-executable || exit 1; \
		kcov --include-path=$(ROOT)/nullray coverage/raw-$$s bin/test_$$s || exit 1; \
	done
	@kcov --merge coverage/html coverage/raw-*
	@echo "coverage: open coverage/html/index.html"

selftest: $(OUT)
	./$(OUT) --self-test

# Print-mode CLI wiring (no provider required).
print-smoke: $(OUT)
	@chmod +x $(ROOT)/scripts/print-smoke.sh
	$(ROOT)/scripts/print-smoke.sh

# Real provider round-trip. Prefers ~/.config/nullray/env (OpenRouter). Falls back to Ollama.
chat-smoke: $(OUT)
	@odin build $(ROOT)/cmd/nullray_chat_smoke -out:bin/nullray_chat_smoke $(COLLECTION) $(LINKER) $(DEFINES)
	@if [ -f "$$HOME/.config/nullray/env" ] && grep -q '^OPENROUTER_API_KEY=' "$$HOME/.config/nullray/env"; then \
		NULLRAY_SANDBOX=off NULLRAY_STREAM=0 ./bin/nullray_chat_smoke && \
		NULLRAY_SANDBOX=off NULLRAY_STREAM=1 ./bin/nullray_chat_smoke ; \
	elif curl -sf --max-time 1 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then \
		NULLRAY_SANDBOX=off NULLRAY_STREAM=0 NULLRAY_PROVIDER=ollama NULLRAY_AGENT_TOOLS=0 ./bin/nullray_chat_smoke && \
		NULLRAY_SANDBOX=off NULLRAY_STREAM=1 NULLRAY_PROVIDER=ollama NULLRAY_AGENT_TOOLS=0 ./bin/nullray_chat_smoke ; \
	else \
		echo 'chat-smoke: skip (no OpenRouter env and ollama not reachable)' ; \
	fi

completions: $(OUT)
	@mkdir -p contrib/completions
	./$(OUT) --completions bash > contrib/completions/nullray.bash
	./$(OUT) --completions zsh > contrib/completions/nullray.zsh
	./$(OUT) --completions fish > contrib/completions/nullray.fish
	./$(OUT) --completions powershell > contrib/completions/nullray.ps1
	./$(OUT) --completions elvish > contrib/completions/nullray.elv
	./$(OUT) --completions nushell > contrib/completions/nullray.nu

man: $(OUT)
	@mkdir -p man
	./$(OUT) --man > man/nullray.1

install: $(OUT) man completions
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(OUT) $(DESTDIR)$(BINDIR)/nullray
	install -d $(DESTDIR)$(MANDIR)
	install -m 644 man/nullray.1 $(DESTDIR)$(MANDIR)/nullray.1
	install -d $(DESTDIR)$(COMPDIR)
	install -m 644 contrib/completions/nullray.bash $(DESTDIR)$(COMPDIR)/nullray.bash
	install -m 644 contrib/completions/nullray.zsh $(DESTDIR)$(COMPDIR)/nullray.zsh
	install -m 644 contrib/completions/nullray.fish $(DESTDIR)$(COMPDIR)/nullray.fish
	install -m 644 contrib/completions/nullray.ps1 $(DESTDIR)$(COMPDIR)/nullray.ps1
	install -m 644 contrib/completions/nullray.elv $(DESTDIR)$(COMPDIR)/nullray.elv
	install -m 644 contrib/completions/nullray.nu $(DESTDIR)$(COMPDIR)/nullray.nu

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/nullray
	rm -f $(DESTDIR)$(MANDIR)/nullray.1
	rm -rf $(DESTDIR)$(COMPDIR)

clean:
	rm -rf bin dist coverage
	rm -f packaging/flatpak/nullray packaging/flatpak/nullray.svg

appimage: $(OUT)
	@mkdir -p dist
	bash scripts/build-appimage.sh $(OUT) dist

flatpak: $(OUT)
	@mkdir -p dist
	bash scripts/build-flatpak.sh $(OUT) dist

docker-build:
	docker build -t nullray:local .

help:
	@printf '%s\n' \
		'Targets:' \
		'  all          build bin/nullray (default)' \
		'  run          build and run' \
		'  test         unit tests + selftest + chat-smoke + print-smoke' \
		'  selftest     headless smoke only' \
		'  chat-smoke   one-turn provider smoke' \
		'  coverage     kcov HTML under coverage/ (needs kcov)' \
		'  completions  write contrib/completions/' \
		'  man          write man/nullray.1' \
		'  install      install binary, man page, completions' \
		'  appimage     build dist/*.AppImage (needs curl, FUSE3 tooling)' \
		'  flatpak      build dist/*.flatpak (needs flatpak-builder)' \
		'  docker-build build local Docker image nullray:local' \
		'  clean        remove bin/ and dist/'
