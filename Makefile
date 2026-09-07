ODIN   ?= odin
ROOT   := $(CURDIR)
OUT    := bin/nullray
PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
MANDIR := $(PREFIX)/share/man/man1
COMPDIR := $(PREFIX)/share/nullray/completions

COLLECTION := -collection:nullray=$(ROOT)/nullray
LINKER     := -extra-linker-flags:"-lcurl"
BUILD_DATE := $(shell date -u +%Y-%m-%d)
BUILD_TIME := $(shell date -u +%H:%M:%S)
DEFINES    := -define:NULLRAY_BUILD_DATE="$(BUILD_DATE)" -define:NULLRAY_BUILD_TIME="$(BUILD_TIME)"

.PHONY: all clean install uninstall run test selftest chat-smoke help completions man

all: $(OUT)

$(OUT): $(shell find cmd/nullray nullray -name '*.odin' 2>/dev/null)
	@mkdir -p bin
	$(ODIN) build $(ROOT)/cmd/nullray -out:$(OUT) $(COLLECTION) $(LINKER) $(DEFINES)

run: $(OUT)
	./$(OUT)

test:
	$(ODIN) test $(ROOT)/nullray/ui $(COLLECTION) -define:ODIN_TEST_THREADS=1
	$(ODIN) test $(ROOT)/nullray/agent $(COLLECTION) -define:ODIN_TEST_THREADS=1
	$(ODIN) test $(ROOT)/nullray/tools $(COLLECTION) -define:ODIN_TEST_THREADS=1
	$(ODIN) test $(ROOT)/nullray/store $(COLLECTION) -define:ODIN_TEST_THREADS=1
	$(ODIN) test $(ROOT)/nullray/sandbox $(COLLECTION) -define:ODIN_TEST_THREADS=1
	$(ODIN) test $(ROOT)/nullray/mcp $(COLLECTION) -define:ODIN_TEST_THREADS=1
	$(ODIN) test $(ROOT)/nullray/provider $(COLLECTION) -define:ODIN_TEST_THREADS=1
	@$(MAKE) --no-print-directory selftest
	@$(MAKE) --no-print-directory chat-smoke

selftest: $(OUT)
	./$(OUT) --self-test

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
	rm -rf bin

help:
	@printf '%s\n' \
		'Targets:' \
		'  all          build bin/nullray (default)' \
		'  run          build and run' \
		'  test         unit tests + selftest + chat-smoke' \
		'  selftest     headless smoke only' \
		'  chat-smoke   one-turn provider smoke' \
		'  completions  write contrib/completions/' \
		'  man          write man/nullray.1' \
		'  install      install binary, man page, completions' \
		'  clean        remove bin/'
