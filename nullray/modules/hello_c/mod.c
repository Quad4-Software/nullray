/* SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
 *
 * Reference C module. Registers a hello_c tool and a /hello-c command.
 * Build compiles this mod.c to mod.o, links it, and calls the entry point
 * below at startup. See docs/modules.md.
 */

#include "../nullray_module.h"

#include <stdlib.h>
#include <string.h>

static char *hello_run(const char *args_json, char **err_out)
{
	(void)args_json;
	(void)err_out;
	return strdup("hello from a C module");
}

/* Module entry. The dir name hello_c becomes the symbol
 * nullray_hello_c_module_init. */
NULLRAY_MODULE_ENTRY(hello_c)
{
	nullray_module_begin("hello_c", "Hello C", "0.1.0",
		"reference C module");
	nullray_module_add_tool(
		"hello_c",
		"Say hello from a C module",
		"{\"type\":\"object\",\"properties\":{},\"required\":[]}",
		NULLRAY_TOOL_READ,
		hello_run);
	nullray_module_add_command("hello-c", "greet via C",
		"Call hello_c and answer plainly.");
	nullray_module_end();
}
