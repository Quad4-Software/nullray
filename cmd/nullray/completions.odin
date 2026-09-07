// SPDX-License-Identifier: 0BSD
/*
Embedded shell completion scripts.
*/

package main

import "core:fmt"
import "core:strings"

print_completions :: proc(shell: string) -> int {
	s := strings.to_lower(strings.trim_space(shell), context.temp_allocator)
	switch s {
	case "bash":
		fmt.print(COMPLETIONS_BASH)
	case "zsh":
		fmt.print(COMPLETIONS_ZSH)
	case "fish":
		fmt.print(COMPLETIONS_FISH)
	case "powershell", "pwsh", "ps1":
		fmt.print(COMPLETIONS_POWERSHELL)
	case "elvish":
		fmt.print(COMPLETIONS_ELVISH)
	case "nushell", "nu":
		fmt.print(COMPLETIONS_NUSHELL)
	case "":
		fmt.eprintln("nullray: --completions needs a shell: bash zsh fish powershell elvish nushell")
		return 2
	case:
		fmt.eprintf("nullray: unknown shell for completions: %s\n", shell)
		fmt.eprintln("supported: bash zsh fish powershell elvish nushell")
		return 2
	}
	return 0
}

COMPLETIONS_BASH :: `# nullray bash completion
_nullray() {
  local cur prev opts providers modes perms sandboxes
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  opts="--help -h --version -V --ephemeral -e --self-test -t --audit --doctor --debug --print -P --ask -q --bare --fail-on-findings --provider -p --model -m --theme --mode --perms --sandbox --workspace -w --session --list-sessions --search-sessions --delete-session --export-session --import-session --as --list-skills --install-skill --uninstall-skill --skills --keys --message-file --out --plan-out --plan-in --output-format --timeout --no-splash --no-subagents --splash --hide-sensitive --list-models --completions --man"
  providers="ollama lmstudio openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure"
  modes="ask plan review edit"
  perms="ask allow yolo"
  sandboxes="off soft warn strict on"
  keys="default neovim emacs"

  case "$prev" in
    --provider|-p) COMPREPLY=( $(compgen -W "$providers" -- "$cur") ); return ;;
    --mode) COMPREPLY=( $(compgen -W "$modes" -- "$cur") ); return ;;
    --perms) COMPREPLY=( $(compgen -W "$perms" -- "$cur") ); return ;;
    --sandbox) COMPREPLY=( $(compgen -W "$sandboxes" -- "$cur") ); return ;;
    --keys) COMPREPLY=( $(compgen -W "$keys" -- "$cur") ); return ;;
    --output-format) COMPREPLY=( $(compgen -W "text json" -- "$cur") ); return ;;
    --completions) COMPREPLY=( $(compgen -W "bash zsh fish powershell elvish nushell" -- "$cur") ); return ;;
    --theme) COMPREPLY=( $(compgen -W "ink ember moss slate rose mono dusk" -- "$cur") ); return ;;
    --workspace|-w|--session|--search-sessions|--delete-session|--export-session|--import-session|--as|--model|-m|--message-file|--out|--plan-out|--plan-in|--install-skill|--uninstall-skill|--skills) COMPREPLY=( $(compgen -f -- "$cur") ); return ;;
  esac
  if [[ "$cur" == -* ]]; then
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
  fi
}
complete -F _nullray nullray
`

COMPLETIONS_ZSH :: `#compdef nullray
_nullray() {
  local -a opts providers modes perms sandboxes shells themes
  opts=(
    '--help[show help]' '-h[show help]'
    '--version[show version]' '-V[show version]'
    '--ephemeral[do not load or save transcripts]' '-e[do not load or save transcripts]'
    '--self-test[headless smoke]' '-t[headless smoke]'
    '--audit[run workspace security scanners]'
    '--doctor[print env and crash dump paths]'
    '--debug[verbose stderr lifecycle logs]'
    '--print[one-shot agent no TUI]' '-P[one-shot agent no TUI]'
    '--ask[simple Q and A]' '-q[simple Q and A]'
    '--bare[skip home MCP and non-workspace skills]'
    '--fail-on-findings[exit 1 when review findings present]'
    '--provider[provider id]:provider:(ollama lmstudio openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure)'
    '-p[provider id]:provider:(ollama lmstudio openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure)'
    '--model[model id]:model:'
    '-m[model id]:model:'
    '--theme[ui theme]:theme:(ink ember moss slate rose mono dusk)'
    '--mode[agent mode]:mode:(ask plan review edit)'
    '--perms[shell policy]:perms:(ask allow yolo)'
    '--sandbox[sandbox mode]:sandbox:(off soft warn strict on)'
    '--workspace[workspace path]:dir:_files -/'
    '-w[workspace path]:dir:_files -/'
    '--session[session name]:session:'
    '--list-sessions[list saved sessions]'
    '--search-sessions[search sessions]:query:'
    '--delete-session[delete named session]:session:'
    '--export-session[export session to --out dir]:session:'
    '--import-session[import session from path]:path:_files'
    '--as[import or install destination name]:name:'
    '--list-skills[list loaded skills]'
    '--install-skill[install skill .md or package]:path:_files'
    '--uninstall-skill[uninstall config skill]:id:'
    '--skills[extra skill root dirs]:path:_files -/'
    '--keys[keybind preset]:keys:(default neovim emacs)'
    '--message-file[prompt file]:file:_files'
    '--out[write final reply or export dir]:file:_files'
    '--plan-out[plan artifact path]:file:_files'
    '--plan-in[load Done Contract plan]:file:_files'
    '--output-format[print output format]:format:(text json)'
    '--timeout[print timeout seconds]:seconds:'
    '--no-splash[skip startup splash]' \
    '--no-subagents[disable subagent task tool]' \
    '--splash[force startup splash]'
    '--hide-sensitive[hide account and API key balances]'
    '--list-models[list models for active provider]'
    '--completions[print shell completions]:shell:(bash zsh fish powershell elvish nushell)'
    '--man[print man page source]'
  )
  _arguments -s : $opts
}
compdef _nullray nullray
`

COMPLETIONS_FISH :: `complete -c nullray -f
complete -c nullray -s h -l help -d 'Show help'
complete -c nullray -s V -l version -d 'Show version'
complete -c nullray -s e -l ephemeral -d 'Do not load or save transcripts'
complete -c nullray -s t -l self-test -d 'Headless smoke'
complete -c nullray -l audit -d 'Run workspace security scanners'
complete -c nullray -l doctor -d 'Print env and crash dump paths'
complete -c nullray -l debug -d 'Verbose stderr lifecycle logs'
complete -c nullray -s P -l print -d 'One-shot agent without TUI'
complete -c nullray -l bare -d 'Skip home MCP and non-workspace skills'
complete -c nullray -l fail-on-findings -d 'Exit 1 when review findings present'
complete -c nullray -s p -l provider -d 'Provider id' -xa 'ollama lmstudio openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure'
complete -c nullray -s m -l model -d 'Model id' -r
complete -c nullray -l theme -d 'UI theme' -xa 'ink ember moss slate rose mono dusk'
complete -c nullray -l mode -d 'Agent mode' -xa 'ask plan review edit'
complete -c nullray -l perms -d 'Shell policy' -xa 'ask allow yolo'
complete -c nullray -l sandbox -d 'Sandbox mode' -xa 'off soft warn strict on'
complete -c nullray -s w -l workspace -d 'Workspace path' -r -F
complete -c nullray -l session -d 'Session name' -r
complete -c nullray -l list-sessions -d 'List saved sessions'
complete -c nullray -l search-sessions -d 'Search sessions' -r
complete -c nullray -l delete-session -d 'Delete named session' -r
complete -c nullray -l export-session -d 'Export session to --out dir' -r
complete -c nullray -l import-session -d 'Import session from path' -r -F
complete -c nullray -l as -d 'Name for import-session or install-skill' -r
complete -c nullray -l list-skills -d 'List loaded skills'
complete -c nullray -l install-skill -d 'Install skill into config' -r -F
complete -c nullray -l uninstall-skill -d 'Uninstall config skill' -r
complete -c nullray -l skills -d 'Extra skill root dirs' -r -F
complete -c nullray -l keys -d 'Keybind preset' -xa 'default neovim emacs'
complete -c nullray -l message-file -d 'Prompt from file' -r -F
complete -c nullray -l out -d 'Write final reply or export dir' -r -F
complete -c nullray -l plan-out -d 'Plan artifact path' -r -F
complete -c nullray -l plan-in -d 'Load Done Contract plan' -r -F
complete -c nullray -l output-format -d 'Print output format' -xa 'text json'
complete -c nullray -l timeout -d 'Print timeout seconds' -r
complete -c nullray -l no-splash -d 'Skip startup splash'
complete -c nullray -l no-subagents -d 'Disable subagent task tool'
complete -c nullray -l splash -d 'Force startup splash'
complete -c nullray -l hide-sensitive -d 'Hide account and API key balances'
complete -c nullray -l list-models -d 'List models for active provider'
complete -c nullray -l completions -d 'Print shell completions' -xa 'bash zsh fish powershell elvish nushell'
complete -c nullray -l man -d 'Print man page source'
`

COMPLETIONS_POWERSHELL :: `Register-ArgumentCompleter -CommandName nullray -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  $opts = @(
    '--help','-h','--version','-V','--ephemeral','-e','--self-test','-t',
    '--audit','--doctor','--debug','--print','-P','--bare','--fail-on-findings',
    '--provider','-p','--model','-m','--theme','--mode','--perms','--sandbox',
    '--workspace','-w','--session','--list-sessions','--search-sessions',
    '--delete-session','--export-session','--import-session','--as',
    '--list-skills','--install-skill','--uninstall-skill','--skills',
    '--keys','--message-file','--out','--plan-out','--plan-in',
    '--output-format','--timeout','--no-splash','--no-subagents','--splash','--hide-sensitive','--list-models','--completions','--man'
  )
  $opts | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
  }
}
`

COMPLETIONS_ELVISH :: `use str
set edit:completion:arg-completer[nullray] = {|@args|
  var flags = [
    --help -h --version -V --ephemeral -e --self-test -t
    --audit --doctor --debug --print -P --bare --fail-on-findings
    --provider -p --model -m --theme --mode --perms --sandbox
    --workspace -w --session --list-sessions --search-sessions
    --delete-session --export-session --import-session --as
    --list-skills --install-skill --uninstall-skill --skills
    --keys --message-file --out --plan-out --plan-in
    --output-format --timeout --no-splash --no-subagents --splash --hide-sensitive --list-models --completions --man
  ]
  put $@flags
}
`

COMPLETIONS_NUSHELL :: `def "nu-complete nullray flags" [] {
  [
    --help -h --version -V --ephemeral -e --self-test -t
    --audit --doctor --debug --print -P --bare --fail-on-findings
    --provider -p --model -m --theme --mode --perms --sandbox
    --workspace -w --session --list-sessions --search-sessions
    --delete-session --export-session --import-session --as
    --list-skills --install-skill --uninstall-skill --skills
    --keys --message-file --out --plan-out --plan-in
    --output-format --timeout --no-splash --no-subagents --splash --hide-sensitive --list-models --completions --man
  ]
}
export extern nullray [
  ...args: string@"nu-complete nullray flags"
]
`

print_man :: proc() {
	fmt.print(MAN_PAGE)
}

MAN_PAGE :: `.TH NULLRAY 1 "2026" "nullray 0.1.0" "User Commands"
.SH NAME
nullray \- Odin coding agent with sandboxed tools
.SH SYNOPSIS
.B nullray
[\fIOPTIONS\fR]
.SH DESCRIPTION
nullray is a terminal coding agent with a custom TUI, Landlock/seccomp sandbox,
OpenAI-compatible providers, and a native tool loop.
.SH OPTIONS
.TP
.BR \-h ", " \-\-help
Show help and exit.
.TP
.BR \-V ", " \-\-version
Show version, build date, and build time.
.TP
.BR \-e ", " \-\-ephemeral
Do not load or save session transcripts.
.TP
.BR \-t ", " \-\-self\-test
Run headless smoke checks and exit.
.TP
.B \-\-audit
Run workspace security scanners and exit. Checks Actions pins, Dockerfiles,
Compose files, common credential patterns, and dependency lock files.
.TP
.B \-\-doctor
Print config paths, key env presence, TTY status, and the latest crash dump path.
.TP
.B \-\-debug
Verbose stderr lifecycle logs. Also set with
.B NULLRAY_DEBUG=1.
.TP
.BR \-P ", " \-\-print
Run one agent turn without the TUI, print the reply, and exit.
Defaults to ephemeral session and mode ask. Prompt from remaining args,
.B \-\-message\-file, or stdin when not a TTY.
.TP
.BR \-q ", " \-\-ask
Run one ephemeral read-only question without the TUI. This never enables
write or shell tools.
.TP
.B \-\-bare
Skip home MCP autoload and non-workspace skills (CI reproducibility).
Explicit
.B NULLRAY_SKILLS
and
.B \-\-skills
roots still load.
.TP
.B \-\-list\-skills
List loaded skills (id, description, source) and exit.
.TP
.B \-\-install\-skill \fIPATH\fR
Copy a skill
.I .md
file or package directory (with
.IR SKILL.md )
into
.IR ~/.config/nullray/skills/ .
Optional
.B \-\-as \fIID\fR
sets the destination id.
.TP
.B \-\-uninstall\-skill \fIID\fR
Remove a skill installed under the config skills directory.
.TP
.B \-\-skills \fIPATH\fR
Add extra skill root directories (comma-separated, flag repeatable).
Same as
.BR NULLRAY_SKILLS .
.TP
.B \-\-fail\-on\-findings
In review mode, exit 1 when the reply ends with FINDINGS: N and N > 0.
.TP
.BR \-p ", " \-\-provider " " \fIID\fR
Select provider: ollama, lmstudio, openai, openai-compat, openrouter, opencode,
opencode-go, anthropic, gemini, groq, deepseek, mistral, together, fireworks, xai, azure.
.TP
.BR \-m ", " \-\-model " " \fINAME\fR
Override the default model for the active provider.
.TP
.B \-\-theme \fINAME\fR
UI theme (ink, dusk, mono, ...).
.TP
.B \-\-mode \fIMODE\fR
Agent mode: ask, plan, review, or edit.
.TP
.B \-\-perms \fIPOLICY\fR
Shell permission policy: ask, allow, or yolo.
Edit under --print requires allow or yolo.
.TP
.B \-\-sandbox \fIMODE\fR
Sandbox mode: off, soft, warn, strict, or on.
.TP
.BR \-w ", " \-\-workspace " " \fIPATH\fR
Workspace root for tools and sandbox.
.TP
.B \-\-session \fINAME\fR
Resume or create a named session under ~/.config/nullray/sessions/.
.TP
.B \-\-list\-sessions
List saved sessions and exit.
.TP
.B \-\-search\-sessions \fIQUERY\fR
Search session names, metadata, and transcript text.
.TP
.B \-\-delete\-session \fINAME\fR
Delete a named session from disk.
.TP
.B \-\-export\-session \fINAME\fR
Copy a session transcript and meta into
.B \-\-out
DIR.
.TP
.B \-\-import\-session \fIPATH\fR
Import a .jsonl (or a directory containing one) into the sessions store.
.TP
.B \-\-as \fINAME\fR
Destination name for
.B \-\-import\-session
or
.B \-\-install\-skill.
.TP
.B \-\-keys \fIPRESET\fR
Keybind preset: default, neovim, or emacs.
.TP
.B \-\-message\-file \fIPATH\fR
Read prompt text from a file (print mode).
.TP
.B \-\-out \fIPATH\fR
Write the final assistant reply to a file, or the export directory for
.B \-\-export\-session.
.TP
.B \-\-plan\-out \fIPATH\fR
Write the plan-mode markdown artifact to this path.
.TP
.B \-\-plan\-in \fIPATH\fR
Load a Done Contract plan for edit apply (print mode auto-approves,
TUI seeds for /approve). Cannot combine with
.BR \-\-plan\-out .
.TP
.B \-\-output\-format \fIFORMAT\fR
Print mode output: text (default) or json.
.TP
.B \-\-timeout \fISEC\fR
Print mode wall-clock timeout in seconds (default 600).
.TP
.B \-\-no\-splash
Skip the startup splash animation.
.TP
.B \-\-splash
Force the startup splash animation.
.TP
.B \-\-list\-models
List models from the active provider and exit.
.TP
.B \-\-completions \fISHELL\fR
Print completion script for bash, zsh, fish, powershell, elvish, or nushell.
.TP
.B \-\-man
Print this man page source to stdout.
.SH ENVIRONMENT
Config file:
.I ~/.config/nullray/env
.PP
Common variables: NULLRAY_PROVIDER, NULLRAY_MODEL, NULLRAY_THEME, NULLRAY_MODE, NULLRAY_PERMS,
NULLRAY_SANDBOX, NULLRAY_WORKSPACE, NULLRAY_SESSION, NULLRAY_EPHEMERAL, NULLRAY_SPLASH,
NULLRAY_KEYS, NULLRAY_STREAM, NULLRAY_HTTP_RETRIES, NULLRAY_FALLBACK_MODELS,
NULLRAY_OPENROUTER_IGNORE, NULLRAY_BARE, NULLRAY_SKILLS, NULLRAY_PRINT_TIMEOUT, NULLRAY_OUT, NULLRAY_PLAN_OUT, NULLRAY_PLAN_IN,
NULLRAY_COLOR, NULLRAY_ALT_SCREEN, NULLRAY_MOUSE, NULLRAY_DEBUG,
OPENROUTER_API_KEY, OLLAMA_HOST, LM_STUDIO_HOST, LM_API_TOKEN.
.SH FILES
.TP
.I ~/.config/nullray/env
Key=value environment overrides.
.TP
.I ~/.config/nullray/skills/
User-installed skills (flat .md or name/SKILL.md packages).
.TP
.I ~/.config/nullray/keys.ini
Key bindings and optional preset= line.
.TP
.I ~/.config/nullray/sessions/
Session transcripts and metadata.
.TP
.I ~/.config/nullray/mcp.json
MCP server autoload config.
.TP
.I .nullray/plans/
Default plan-mode markdown artifacts under the workspace.
.SH EXAMPLES
.nf
nullray --provider ollama --model gemma3:4b
nullray --print --mode ask "What does session_init do?"
nullray --print --mode review --fail-on-findings "Review the staged diff"
git diff | nullray --print --mode review --bare "Review this PR diff"
nullray --list-models
nullray --list-sessions
nullray --list-skills
nullray --install-skill ./pack/my-skill --as demo
nullray --skills ~/extra-skills --print "hello"
nullray --export-session mywork --out ./backup
nullray --import-session ./backup/mywork.jsonl --as restored
nullray --completions zsh > ~/.zsh/completions/_nullray
.fi
.SH SEE ALSO
Documentation in the project README.
.SH AUTHOR
Quad4 Software
`
