// SPDX-License-Identifier: 0BSD
package provider

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(test)
test_quirk_tool_xml_in_reasoning_qwen :: proc(t: ^testing.T) {
	defer quirk_reset_config_for_test()
	os.set_env(constants.ENV_QUIRKS, "tool_xml_in_reasoning")

	reasoning := strings.trim_space(`
Plan: read the file first.

<tool_call>
<function=read_file>
<parameter=path>/tmp/example.txt</parameter>
</tool_call>
`)

	res := Chat_Response{
		ok = true,
		reasoning = strings.clone(reasoning),
	}
	defer destroy_chat_response(&res)

	apply_quirks(&res, "qwen2.5-coder:7b")

	testing.expect_value(t, len(res.tool_calls), 1)
	testing.expect_value(t, res.tool_calls[0].name, "read_file")
	testing.expect(t, strings.contains(res.tool_calls[0].arguments, `"path"`))
	testing.expect(t, strings.contains(res.tool_calls[0].arguments, `example.txt`))
	testing.expect(t, strings.contains(res.reasoning, "Plan: read the file first"))
	testing.expect(t, !strings.contains(res.reasoning, "<tool_call>"))
}

@(test)
test_quirk_tool_xml_default_off_non_qwen :: proc(t: ^testing.T) {
	defer quirk_reset_config_for_test()
	os.unset_env(constants.ENV_QUIRKS)

	reasoning := `<tool_call><function=list_dir><parameter=path>.</parameter></tool_call>`
	res := Chat_Response{
		ok = true,
		reasoning = strings.clone(reasoning),
	}
	defer destroy_chat_response(&res)

	apply_quirks(&res, "llama3.2")

	testing.expect_value(t, len(res.tool_calls), 0)
}

@(test)
test_quirk_reasoning_only_stall :: proc(t: ^testing.T) {
	defer quirk_reset_config_for_test()
	os.set_env(constants.ENV_QUIRKS, "reasoning_only_stall")

	res := Chat_Response{
		ok = true,
		reasoning = strings.clone("Here is the answer after thinking."),
	}
	defer destroy_chat_response(&res)

	apply_quirks(&res, "gpt-4")

	testing.expect_value(t, res.content, "Here is the answer after thinking.")
	testing.expect_value(t, len(res.tool_calls), 0)
}

@(test)
test_quirk_disabled_by_env :: proc(t: ^testing.T) {
	defer quirk_reset_config_for_test()
	os.set_env(constants.ENV_QUIRKS, "0")

	res := Chat_Response{
		ok = true,
		reasoning = strings.clone("stall text"),
	}
	defer destroy_chat_response(&res)

	apply_quirks(&res, "qwen3")

	testing.expect_value(t, len(res.content), 0)
}
