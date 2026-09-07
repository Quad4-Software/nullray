// SPDX-License-Identifier: 0BSD
package app

SETUP_BYOK_NOTE :: "Subscription SSO for Anthropic, OpenAI, and Cursor is BYOK only."

// Device OAuth placeholder until browser launch and polling are implemented.
SETUP_OPENROUTER_NOTE :: "OpenRouter device OAuth is not available. Paste OPENROUTER_API_KEY."

setup_oauth_note :: proc(provider_id: string) -> string {
	if provider_id == "openrouter" {
		return SETUP_OPENROUTER_NOTE
	}
	return SETUP_BYOK_NOTE
}
