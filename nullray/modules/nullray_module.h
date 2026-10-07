/* SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
 *
 * Nullray C module API. A C module is a directory nullray/modules/<id>/
 * containing a mod.c that defines NULLRAY_MODULE_ENTRY(<id>) and calls the
 * registration functions below. The build compiles mod.c, links it, and
 * calls the entry point at startup. See docs/modules.md.
 *
 * Result contract: a tool run fn returns a malloc'd result string or NULL,
 * and may write a malloc'd error string through err_out. Nullray copies
 * then free()s both. args_json is only valid for the duration of the call.
 */
#ifndef NULLRAY_MODULE_H
#define NULLRAY_MODULE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef char *(*nullray_tool_run_fn)(const char *args_json, char **err_out);

/* Tool kinds gate sandbox/permission behavior. */
#define NULLRAY_TOOL_READ  0 /* read-only, safe to speculate */
#define NULLRAY_TOOL_WRITE 1 /* may modify files or state */
#define NULLRAY_TOOL_SHELL 2 /* executes commands */

/* Registration. Call begin, then add_tool/add_command any number of
 * times, then end. The module registers on end. */
void nullray_module_begin(const char *id, const char *name,
                          const char *version, const char *description);
void nullray_module_add_tool(const char *name, const char *description,
                             const char *schema_json, int kind,
                             nullray_tool_run_fn run);
void nullray_module_add_command(const char *name, const char *help,
                                const char *prompt);
void nullray_module_end(void);

/* NULLRAY_MODULE_ENTRY(my_id) defines the entry point the build calls:
 * void nullray_my_id_module_init(void). Dir names must be [a-z0-9_]. */
#define NULLRAY_JOIN2(a, b) a##b
#define NULLRAY_JOIN(a, b) NULLRAY_JOIN2(a, b)
#define NULLRAY_MODULE_ENTRY(id) \
	void NULLRAY_JOIN(nullray_, NULLRAY_JOIN(id, _module_init))(void)

#ifdef __cplusplus
}
#endif

#endif /* NULLRAY_MODULE_H */
