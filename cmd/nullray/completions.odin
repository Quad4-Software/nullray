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
  opts="--help -h --version -V --ephemeral -e --self-test -t --audit --doctor --debug --print -P --ask -q --bare --fail-on-findings --provider -p --model -m --theme --mode --hunt --perms --gate --sandbox --workspace -w --session --list-sessions --inspect-session --follow --search-sessions --delete-session --rename-session --force --export-session --import-session --as --list-skills --install-skill --uninstall-skill --skills --keys --message-file --out --plan-out --plan-in --output-format --print-strict --auto --usage --timeout --no-splash --no-subagents --splash --hide-sensitive --list-models --completions --man"
  providers="ollama lmstudio llamacpp openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure cerebras cohere nvidia dashscope"
  modes="ask plan review edit"
  hunts="auto balanced explore oracle adversarial"
  perms="ask allow yolo"
  sandboxes="off soft warn strict on"
  keys="default neovim emacs"

  case "$prev" in
    --provider|-p) COMPREPLY=( $(compgen -W "$providers" -- "$cur") ); return ;;
    --mode) COMPREPLY=( $(compgen -W "$modes" -- "$cur") ); return ;;
    --hunt) COMPREPLY=( $(compgen -W "$hunts" -- "$cur") ); return ;;
    --perms) COMPREPLY=( $(compgen -W "$perms" -- "$cur") ); return ;;
    --gate) COMPREPLY=( $(compgen -W "0 1 2 3 ask allow yolo" -- "$cur") ); return ;;
    --sandbox) COMPREPLY=( $(compgen -W "$sandboxes" -- "$cur") ); return ;;
    --keys) COMPREPLY=( $(compgen -W "$keys" -- "$cur") ); return ;;
    --output-format) COMPREPLY=( $(compgen -W "text json" -- "$cur") ); return ;;
    --completions) COMPREPLY=( $(compgen -W "bash zsh fish powershell elvish nushell" -- "$cur") ); return ;;
    --theme) COMPREPLY=( $(compgen -W "ink ember moss slate rose mono dusk" -- "$cur") ); return ;;
    --workspace|-w|--session|--search-sessions|--delete-session|--rename-session|--export-session|--import-session|--as|--model|-m|--message-file|--out|--plan-out|--plan-in|--install-skill|--uninstall-skill|--skills) COMPREPLY=( $(compgen -f -- "$cur") ); return ;;
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
    '--provider[provider id]:provider:(ollama lmstudio llamacpp openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure cerebras cohere nvidia dashscope)'
    '-p[provider id]:provider:(ollama lmstudio llamacpp openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure cerebras cohere nvidia dashscope)'
    '--model[model id]:model:'
    '-m[model id]:model:'
    '--theme[ui theme]:theme:(ink ember moss slate rose mono dusk)'
    '--mode[agent mode]:mode:(ask plan review edit)'
    '--hunt[vuln hunt profile]:profile:(auto balanced explore oracle adversarial)'
    '--perms[shell policy]:perms:(ask allow yolo)'
    '--gate[tool gate]:gate:(0 1 2 3 ask allow yolo)'
    '--sandbox[sandbox mode]:sandbox:(off soft warn strict on)'
    '--workspace[workspace path]:dir:_files -/'
    '-w[workspace path]:dir:_files -/'
    '--session[session name]:session:'
    '--list-sessions[list saved sessions]'
    '--search-sessions[search sessions]:query:'
    '--delete-session[delete named session]:session:'
    '--rename-session[rename named session]:session:'
    '--force[overwrite on rename]'
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
    '--print-strict[strict print exit codes]'
    '--auto[autonomous edit mode]'
    '--usage[print token usage summary]'
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
