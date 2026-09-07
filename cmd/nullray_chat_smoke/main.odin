/*
Headless one-turn chat smoke. Loads ~/.config/nullray/env when present.
*/

package main

import "core:fmt"
import "core:os"
import "core:time"
import "nullray:config"
import "nullray:http"
import "nullray:provider"
import "nullray:session"
import "nullray:tools"

main :: proc() {
	if _, err := config.load_env_file(); err != "" {
		fmt.eprintln("nullray_chat_smoke: config:", err)
	}

	tools.tools_init()
	defer tools.tools_destroy()
	if !http.global_init() {
		fmt.eprintln("nullray_chat_smoke: curl init failed")
		os.exit(1)
	}
	defer http.global_cleanup()

	reg: provider.Registry
	provider.registry_init(&reg)
	defer provider.registry_destroy(&reg)

	p := provider.registry_active(&reg)
	if p == nil || p.chat == nil {
		fmt.eprintln("nullray_chat_smoke: no provider")
		os.exit(1)
	}
	fmt.printf("nullray_chat_smoke: provider=%s model=%s\n", p.id, p.default_model)

	if p.id == "openrouter" {
		if len(p.api_key) == 0 {
			fmt.eprintln("nullray_chat_smoke: OPENROUTER_API_KEY missing")
			os.exit(1)
		}
		bal := provider.openrouter_fetch_balance(p.api_key)
		defer delete(bal.err)
		label := provider.openrouter_balance_label(bal)
		defer delete(label)
		fmt.println("nullray_chat_smoke: credits", label)
		if !bal.ok {
			fmt.eprintln("nullray_chat_smoke: credit fetch failed")
			os.exit(1)
		}
	}

	s: session.Session
	session.session_init(&s)
	defer session.session_destroy(&s)
	s.tools_enabled = false
	s.persist = false

	session.session_push_user(&s, "Reply with exactly: ok")
	session.session_start_chat(&s, p)
	ok := false
	for _ in 0 ..< 400 {
		_ = session.session_poll(&s)
		if !s.busy {
			ok = true
			break
		}
		time.sleep(50 * time.Millisecond)
	}
	if !ok {
		fmt.eprintln("nullray_chat_smoke: timed out status=", s.status)
		os.exit(1)
	}
	if len(s.status) >= 5 && s.status[:5] == "error" {
		fmt.eprintln("nullray_chat_smoke:", s.status)
		os.exit(1)
	}
	found := false
	for m in s.messages {
		if m.role == .Assistant && len(m.content) > 0 {
			found = true
			fmt.println("nullray_chat_smoke: reply", m.content)
			break
		}
	}
	if !found {
		fmt.eprintln("nullray_chat_smoke: no assistant reply")
		os.exit(1)
	}
	fmt.printf(
		"nullray_chat_smoke: ok usage in=%d out=%d total=%d\n",
		s.last_usage.prompt_tokens,
		s.last_usage.completion_tokens,
		s.last_usage.total_tokens,
	)
}
