// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package session

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"

@(test)
test_session_scrub_and_forget :: proc(t: ^testing.T) {
	prev, had := os.lookup_env(constants.ENV_PRIVACY_REDACT, context.temp_allocator)
	os.set_env(constants.ENV_PRIVACY_REDACT, "1")
	defer {
		if had {
			os.set_env(constants.ENV_PRIVACY_REDACT, prev)
		} else {
			os.unset_env(constants.ENV_PRIVACY_REDACT)
		}
	}

	s: Session
	s.persist = false
	s.messages = make([dynamic]provider.Message)
	defer {
		for m in s.messages {
			provider.destroy_message(m)
		}
		delete(s.messages)
	}

	append(&s.messages, provider.Message{role = .User, content = strings.clone("keep me sk-abcXYZ123456789")})
	append(&s.messages, provider.Message{role = .Assistant, content = strings.clone("saw it")})
	n := session_scrub_all(&s)
	testing.expect(t, n >= 1)
	testing.expect(t, !strings.contains(s.messages[0].content, "sk-abcXYZ123456789"))

	append(&s.messages, provider.Message{role = .User, content = strings.clone("forget-this-unique-token")})
	append(&s.messages, provider.Message{role = .Assistant, content = strings.clone("ok")})
	f := session_forget_matching(&s, "forget-this-unique")
	testing.expect(t, f >= 1)
	testing.expect(t, strings.contains(s.messages[len(s.messages) - 2].content, "[forgotten]") ||
		strings.contains(s.messages[len(s.messages) - 1].content, "[forgotten]"))

	before := len(s.messages)
	_ = session_forget_last_user(&s)
	testing.expect(t, len(s.messages) < before)
}
