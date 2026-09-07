# nullray bash completion
_nullray() {
  local cur prev opts providers modes perms sandboxes
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  opts="--help -h --version -V --ephemeral -e --self-test -t --audit --doctor --debug --print -P --ask -q --bare --fail-on-findings --provider -p --model -m --theme --mode --perms --sandbox --workspace -w --session --list-sessions --search-sessions --delete-session --export-session --import-session --as --list-skills --install-skill --uninstall-skill --skills --keys --message-file --out --plan-out --plan-in --output-format --print-strict --auto --usage --timeout --no-splash --no-subagents --splash --hide-sensitive --list-models --completions --man"
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
