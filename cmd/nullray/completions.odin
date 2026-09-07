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
  opts="--help -h --version -V --ephemeral -e --self-test -t --provider -p --model -m --theme --mode --perms --sandbox --workspace -w --session --keys --no-splash --splash --list-models --completions --man"
  providers="ollama lmstudio openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure"
  modes="ask plan edit"
  perms="ask allow yolo"
  sandboxes="on off landlock seccomp"
  keys="default neovim emacs"

  case "$prev" in
    --provider|-p) COMPREPLY=( $(compgen -W "$providers" -- "$cur") ); return ;;
    --mode) COMPREPLY=( $(compgen -W "$modes" -- "$cur") ); return ;;
    --perms) COMPREPLY=( $(compgen -W "$perms" -- "$cur") ); return ;;
    --sandbox) COMPREPLY=( $(compgen -W "$sandboxes" -- "$cur") ); return ;;
    --keys) COMPREPLY=( $(compgen -W "$keys" -- "$cur") ); return ;;
    --completions) COMPREPLY=( $(compgen -W "bash zsh fish powershell elvish nushell" -- "$cur") ); return ;;
    --theme) COMPREPLY=( $(compgen -W "ink ember moss slate rose mono dusk" -- "$cur") ); return ;;
    --workspace|-w|--session|--model|-m) COMPREPLY=( $(compgen -f -- "$cur") ); return ;;
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
    '--provider[provider id]:provider:(ollama lmstudio openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure)'
    '-p[provider id]:provider:(ollama lmstudio openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure)'
    '--model[model id]:model:'
    '-m[model id]:model:'
    '--theme[ui theme]:theme:(ink ember moss slate rose mono dusk)'
    '--mode[agent mode]:mode:(ask plan edit)'
    '--perms[shell policy]:perms:(ask allow yolo)'
    '--sandbox[sandbox mode]:sandbox:(on off landlock seccomp)'
    '--workspace[workspace path]:dir:_files -/'
    '-w[workspace path]:dir:_files -/'
    '--session[session name]:session:'
    '--keys[keybind preset]:keys:(default neovim emacs)'
    '--no-splash[skip startup splash]'
    '--splash[force startup splash]'
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
complete -c nullray -s p -l provider -d 'Provider id' -xa 'ollama lmstudio openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure'
complete -c nullray -s m -l model -d 'Model id' -r
complete -c nullray -l theme -d 'UI theme' -xa 'ink ember moss slate rose mono dusk'
complete -c nullray -l mode -d 'Agent mode' -xa 'ask plan edit'
complete -c nullray -l perms -d 'Shell policy' -xa 'ask allow yolo'
complete -c nullray -l sandbox -d 'Sandbox mode' -xa 'on off landlock seccomp'
complete -c nullray -s w -l workspace -d 'Workspace path' -r -F
complete -c nullray -l session -d 'Session name' -r
complete -c nullray -l keys -d 'Keybind preset' -xa 'default neovim emacs'
complete -c nullray -l no-splash -d 'Skip startup splash'
complete -c nullray -l splash -d 'Force startup splash'
complete -c nullray -l list-models -d 'List models for active provider'
complete -c nullray -l completions -d 'Print shell completions' -xa 'bash zsh fish powershell elvish nushell'
complete -c nullray -l man -d 'Print man page source'
`

COMPLETIONS_POWERSHELL :: `Register-ArgumentCompleter -CommandName nullray -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  $opts = @(
    '--help','-h','--version','-V','--ephemeral','-e','--self-test','-t',
    '--provider','-p','--model','-m','--theme','--mode','--perms','--sandbox',
    '--workspace','-w','--session','--keys','--no-splash','--splash','--list-models','--completions','--man'
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
    --provider -p --model -m --theme --mode --perms --sandbox
    --workspace -w --session --keys --no-splash --splash --list-models --completions --man
  ]
  put $@flags
}
`

COMPLETIONS_NUSHELL :: `def "nu-complete nullray flags" [] {
  [
    --help -h --version -V --ephemeral -e --self-test -t
    --provider -p --model -m --theme --mode --perms --sandbox
    --workspace -w --session --keys --no-splash --splash --list-models --completions --man
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
Agent mode: ask, plan, or edit.
.TP
.B \-\-perms \fIPOLICY\fR
Shell permission policy: ask, allow, or yolo.
.TP
.B \-\-sandbox \fIMODE\fR
Sandbox mode (on, off, landlock, seccomp, ...).
.TP
.BR \-w ", " \-\-workspace " " \fIPATH\fR
Workspace root for tools and sandbox.
.TP
.B \-\-session \fINAME\fR
Resume or create a named session.
.TP
.B \-\-keys \fIPRESET\fR
Keybind preset: default, neovim, or emacs.
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
NULLRAY_KEYS, NULLRAY_STREAM, OPENROUTER_API_KEY, OLLAMA_HOST, LM_STUDIO_HOST, LM_API_TOKEN.
.SH FILES
.TP
.I ~/.config/nullray/env
Key=value environment overrides.
.TP
.I ~/.config/nullray/keys.ini
Key bindings and optional preset= line.
.TP
.I ~/.config/nullray/sessions/
Session transcripts and metadata.
.TP
.I ~/.config/nullray/mcp.json
MCP server autoload config.
.SH EXAMPLES
.nf
nullray --provider ollama --model gemma3:4b
nullray --list-models
nullray --completions zsh > ~/.zsh/completions/_nullray
.fi
.SH SEE ALSO
Documentation in the project README.
.SH AUTHOR
Quad4 Software
`
