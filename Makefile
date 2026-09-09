ODIN   ?= odin
ROOT   := $(CURDIR)
CC     ?= cc
AR     ?= ar

ifeq ($(OS),Windows_NT)
  OUT := bin/nullray.exe
  TLS_LIB := lib/libnullray_tls.a
  # Winsock for the TLS shim. The archive is pulled in via foreign import.
  LINKER := -extra-linker-flags:"-lws2_32"
else
  OUT := bin/nullray
  TLS_LIB := lib/libnullray_tls.a
  LINKER :=
endif

PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
MANDIR := $(PREFIX)/share/man/man1
COMPDIR := $(PREFIX)/share/nullray/completions
BASHCOMPDIR := $(PREFIX)/share/bash-completion/completions
ZSHCOMPDIR := $(PREFIX)/share/zsh/site-functions
FISHCOMPDIR := $(PREFIX)/share/fish/vendor_completions.d

COLLECTION := -collection:nullray=$(ROOT)/nullray
BUILD_DATE := $(shell date -u +%Y-%m-%d)
BUILD_TIME := $(shell date -u +%H:%M:%S)
DEFINES    := -define:NULLRAY_BUILD_DATE="$(BUILD_DATE)" -define:NULLRAY_BUILD_TIME="$(BUILD_TIME)"

MBEDTLS_DIR := $(ROOT)/vendor/mbedtls
MBEDTLS_INC := $(MBEDTLS_DIR)/include
MBEDTLS_LIB := $(MBEDTLS_DIR)/library
NGHTTP2_DIR := $(ROOT)/vendor/nghttp2
NGHTTP2_INC := $(NGHTTP2_DIR)/include
NGHTTP2_LIB := $(NGHTTP2_DIR)/lib
MLKEM_DIR   := $(ROOT)/vendor/mlkem-native
MLKEM_INC   := $(MLKEM_DIR)/mlkem
TLS_BUILD   := $(ROOT)/lib/mbedtls-objs
TLS_CFLAGS  := -Os -fPIC -I$(MBEDTLS_INC) -I$(MBEDTLS_DIR) -I$(MBEDTLS_LIB) -I$(MLKEM_INC)
H2_CFLAGS   := -Os -fPIC -DHAVE_CONFIG_H -DNGHTTP2_STATICLIB -DBUILDING_NGHTTP2 \
	-I$(NGHTTP2_DIR) -I$(NGHTTP2_INC)
MLKEM_CFLAGS := -Os -fPIC -std=c99 -I$(MLKEM_INC) -DMLK_CONFIG_PARAMETER_SET=768

# Client-only object set (matches trimmed mbedtls_config.h).
# TLS 1.3 needs PSA crypto objects plus ssl_tls13_{client,generic,keys}.
MBEDTLS_SKIP := \
	net_sockets.c timing.c \
	ssl_tls13_server.c \
	ssl_ticket.c ssl_cache.c ssl_cookie.c \
	debug.c dhm.c camellia.c aria.c des.c ccm.c cmac.c nist_kw.c \
	ripemd160.c md5.c pkcs7.c x509_crl.c x509_csr.c \
	x509write_crt.c x509write_csr.c pkwrite.c \
	havege.c memory_buffer_alloc.c lms.c lms_helpers.c \
	psa_crypto_storage.c psa_its_file.c psa_crypto_se.c

MBEDTLS_SRCS := $(filter-out $(MBEDTLS_SKIP),$(notdir $(wildcard $(MBEDTLS_LIB)/*.c)))
MBEDTLS_OBJS := $(addprefix $(TLS_BUILD)/,$(MBEDTLS_SRCS:.c=.o))
SHIM_OBJ     := $(TLS_BUILD)/nullray_tls_shim.o
PQ_OBJ       := $(TLS_BUILD)/nullray_tls_pq.o
MLKEM_OBJ    := $(TLS_BUILD)/mlkem_native.o

NGHTTP2_SRCS := $(notdir $(wildcard $(NGHTTP2_LIB)/*.c))
NGHTTP2_OBJS := $(addprefix $(TLS_BUILD)/nghttp2_,$(NGHTTP2_SRCS:.c=.o))
H2_SHIM_OBJ  := $(TLS_BUILD)/nullray_h2_shim.o

.PHONY: all clean install uninstall run test selftest chat-smoke print-smoke rag-live coverage help completions man \
	appimage appimage-sdk sdk-smoke flatpak docker-build debug tls-lib tls-size

TEST_SUITES := ui agent tools skills session store sandbox memory rag mcp provider app config subagent elevate structure secure hooks vcs run patch http
TEST_FLAGS  := $(COLLECTION) -define:ODIN_TEST_THREADS=1 -debug

all: $(OUT)

tls-lib: $(TLS_LIB)

$(TLS_BUILD):
	@mkdir -p $(TLS_BUILD)

$(TLS_BUILD)/%.o: $(MBEDTLS_LIB)/%.c $(MBEDTLS_INC)/mbedtls/mbedtls_config.h | $(TLS_BUILD)
	$(CC) $(TLS_CFLAGS) -c $< -o $@

$(TLS_BUILD)/nghttp2_%.o: $(NGHTTP2_LIB)/%.c $(NGHTTP2_DIR)/config.h | $(TLS_BUILD)
	$(CC) $(H2_CFLAGS) -c $< -o $@

$(SHIM_OBJ): $(MBEDTLS_DIR)/nullray_tls_shim.c $(MBEDTLS_DIR)/nullray_tls_shim.h $(MBEDTLS_INC)/mbedtls/mbedtls_config.h | $(TLS_BUILD)
	$(CC) $(TLS_CFLAGS) -c $< -o $@

$(PQ_OBJ): $(MBEDTLS_DIR)/nullray_tls_pq.c $(MBEDTLS_DIR)/nullray_tls_pq.h $(MBEDTLS_INC)/mbedtls/mbedtls_config.h | $(TLS_BUILD)
	$(CC) $(TLS_CFLAGS) -c $< -o $@

$(MLKEM_OBJ): $(MLKEM_INC)/mlkem_native.c $(MLKEM_INC)/mlkem_native.h $(MLKEM_INC)/mlkem_native_config.h | $(TLS_BUILD)
	$(CC) $(MLKEM_CFLAGS) -c $< -o $@

$(H2_SHIM_OBJ): $(NGHTTP2_DIR)/nullray_h2_shim.c $(NGHTTP2_DIR)/nullray_h2_shim.h | $(TLS_BUILD)
	$(CC) $(H2_CFLAGS) -c $< -o $@

$(TLS_LIB): $(MBEDTLS_OBJS) $(SHIM_OBJ) $(PQ_OBJ) $(MLKEM_OBJ) $(NGHTTP2_OBJS) $(H2_SHIM_OBJ)
	@mkdir -p lib
	$(AR) rcs $@ $^
	@ls -la $@

tls-size: $(TLS_LIB) $(OUT)
	@echo "libnullray_tls.a: $$(wc -c < $(TLS_LIB)) bytes"
	@echo "bin/nullray: $$(wc -c < $(OUT)) bytes"
	@command -v strip >/dev/null && strip -o /tmp/nullray.stripped $(OUT) && \
		echo "bin/nullray stripped: $$(wc -c < /tmp/nullray.stripped) bytes" || true

$(OUT): $(TLS_LIB) $(shell find cmd/nullray nullray -name '*.odin' 2>/dev/null)
	@mkdir -p bin
	$(ODIN) build $(ROOT)/cmd/nullray -out:$(OUT) $(COLLECTION) $(LINKER) $(DEFINES)

debug: $(TLS_LIB)
	@mkdir -p bin
	$(ODIN) build $(ROOT)/cmd/nullray -out:$(OUT) $(COLLECTION) $(LINKER) $(DEFINES) -debug
	@echo "built $(OUT) with -debug (richer crash backtraces)"

run: $(OUT)
	./$(OUT)

test: $(TLS_LIB)
	@for s in $(TEST_SUITES); do \
		$(ODIN) test $(ROOT)/nullray/$$s $(COLLECTION) -define:ODIN_TEST_THREADS=1 || exit 1; \
	done
	@$(MAKE) --no-print-directory selftest
	@$(MAKE) --no-print-directory chat-smoke
	@$(MAKE) --no-print-directory print-smoke

# Local HTML coverage via kcov (Linux). Does not upload or gate CI.
coverage: $(TLS_LIB)
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

# Live RAG + OpenRouter embed/chat (requires OPENROUTER_API_KEY).
rag-live: $(OUT)
	@chmod +x $(ROOT)/scripts/rag-live.sh
	$(ROOT)/scripts/rag-live.sh

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
	install -d $(DESTDIR)$(BASHCOMPDIR)
	install -m 644 contrib/completions/nullray.bash $(DESTDIR)$(BASHCOMPDIR)/nullray
	install -d $(DESTDIR)$(ZSHCOMPDIR)
	install -m 644 contrib/completions/nullray.zsh $(DESTDIR)$(ZSHCOMPDIR)/_nullray
	install -d $(DESTDIR)$(FISHCOMPDIR)
	install -m 644 contrib/completions/nullray.fish $(DESTDIR)$(FISHCOMPDIR)/nullray.fish

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/nullray
	rm -f $(DESTDIR)$(MANDIR)/nullray.1
	rm -rf $(DESTDIR)$(COMPDIR)
	rm -f $(DESTDIR)$(BASHCOMPDIR)/nullray
	rm -f $(DESTDIR)$(ZSHCOMPDIR)/_nullray
	rm -f $(DESTDIR)$(FISHCOMPDIR)/nullray.fish

clean:
	rm -rf bin dist coverage lib
	rm -f packaging/flatpak/nullray packaging/flatpak/nullray.svg

appimage: $(OUT)
	@mkdir -p dist
	bash scripts/build-appimage.sh $(OUT) dist

appimage-sdk: $(OUT)
	@mkdir -p dist
	bash scripts/build-appimage-sdk.sh $(OUT) dist

sdk-smoke:
	@chmod +x scripts/sdk-smoke.sh
	bash scripts/sdk-smoke.sh

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
		'  rag-live     live OpenRouter embed + Mercury RAG recall' \
		'  coverage     kcov HTML under coverage/ (needs kcov)' \
		'  completions  fill contrib/completions/' \
		'  man          write man/nullray.1' \
		'  install      install binary, man page, completions' \
		'  appimage     slim dist/*.AppImage (needs curl or NULLRAY_APPIMAGE_TOOLS)' \
		'  appimage-sdk airgap SDK AppImage (odin + src + pack tools)' \
		'  sdk-smoke    /tmp extract, rebuild, pack slim from SDK image' \
		'  flatpak      build dist/*.flatpak (needs flatpak-builder)' \
		'  docker-build build local Docker image nullray:local' \
		'  tls-lib      build lib/libnullray_tls.a from vendored Mbed TLS + nghttp2' \
		'  tls-size     print TLS archive and binary sizes' \
		'  clean        remove bin/, dist/, and lib/'
