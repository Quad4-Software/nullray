# nullray bash completion
_nullray() {
  local cur prev opts providers modes perms sandboxes
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  opts="--help -h --version -V --ephemeral -e --self-test -t --audit --review --review-scope --base --staged --unstaged --include-untracked --paths --doctor --debug --print -P --stream --trace --patch-out --no-adopt --ask -q --acp --serve --connect --attach --bare --fail-on-findings --provider -p --model -m --theme --mode --hunt --perms --gate --sandbox --workspace -w --session --list-sessions --inspect-session --follow --search-sessions --delete-session --rename-session --force --export-session --import-session --as --list-skills --distill --skills --keys --message-file --image --audio --video --media --out --plan-out --plan-in --output-format --print-strict --auto --usage --samples --architect --timeout --no-splash --no-subagents --splash --hide-sensitive --list-models --list-modules --completions --man"
  cmds="serve attach watch"
  providers="ollama lmstudio llamacpp openai openai-compat openrouter opencode opencode-go anthropic gemini groq deepseek mistral together fireworks xai azure cerebras cohere nvidia dashscope"
  modes="ask plan review edit orchestrate"
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
    --review-scope) COMPREPLY=( $(compgen -W "working staged unstaged base" -- "$cur") ); return ;;
    --keys) COMPREPLY=( $(compgen -W "$keys" -- "$cur") ); return ;;
    --output-format) COMPREPLY=( $(compgen -W "text json" -- "$cur") ); return ;;
    --completions) COMPREPLY=( $(compgen -W "bash zsh fish powershell elvish nushell" -- "$cur") ); return ;;
    --theme) COMPREPLY=( $(compgen -W "ink ember moss slate rose mono dusk" -- "$cur") ); return ;;
    --workspace|-w|--session|--search-sessions|--delete-session|--rename-session|--export-session|--import-session|--as|--model|-m|--message-file|--image|--audio|--video|--media|--out|--plan-out|--plan-in|--skills|--base|--paths) COMPREPLY=( $(compgen -f -- "$cur") ); return ;;
  esac
  if [[ "$cur" == -* ]]; then
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
  elif [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
  fi
}
complete -F _nullray nullray
