complete -c nullray -f
complete -c nullray -s h -l help -d 'Show help'
complete -c nullray -s V -l version -d 'Show version'
complete -c nullray -s e -l ephemeral -d 'Do not load or save transcripts'
complete -c nullray -s t -l self-test -d 'Headless smoke'
complete -c nullray -s p -l provider -d 'Provider id' -xa 'ollama lmstudio openrouter opencode opencode-go'
complete -c nullray -s m -l model -d 'Model id' -r
complete -c nullray -l theme -d 'UI theme' -xa 'ink ember moss slate rose mono dusk'
complete -c nullray -l mode -d 'Agent mode' -xa 'ask plan edit'
complete -c nullray -l perms -d 'Shell policy' -xa 'ask allow yolo'
complete -c nullray -l sandbox -d 'Sandbox mode' -xa 'on off landlock seccomp'
complete -c nullray -s w -l workspace -d 'Workspace path' -r -F
complete -c nullray -l session -d 'Session name' -r
complete -c nullray -l list-models -d 'List models for active provider'
complete -c nullray -l completions -d 'Print shell completions' -xa 'bash zsh fish powershell elvish nushell'
complete -c nullray -l man -d 'Print man page source'
