// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package session

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"

@(test)
test_session_push_scrubs_secrets :: proc(t: ^testing.T) {
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

	session_push_user(&s, "my key is sk-testKEY1234567890 and card 4111111111111111")
	testing.expect(t, len(s.messages) == 1)
	testing.expect(t, !strings.contains(s.messages[0].content, "sk-testKEY1234567890"))
	testing.expect(t, !strings.contains(s.messages[0].content, "4111111111111111"))
	testing.expect(t, strings.contains(s.messages[0].content, "[redacted]"))

	session_push_tool(&s, "run_shell", "password=sekrit api_key=abc")
	testing.expect(t, len(s.messages) == 2)
	testing.expect(t, !strings.contains(s.messages[1].content, "sekrit"))
	testing.expect(t, strings.contains(s.messages[1].content, "password="))
}
