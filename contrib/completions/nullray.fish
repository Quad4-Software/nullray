complete -c nullray -f
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
complete -c nullray -l print-strict -d 'Strict print exit codes'
complete -c nullray -l auto -d 'Autonomous edit mode'
complete -c nullray -l usage -d 'Print token usage summary'
complete -c nullray -l timeout -d 'Print timeout seconds' -r
complete -c nullray -l no-splash -d 'Skip startup splash'
complete -c nullray -l no-subagents -d 'Disable subagent task tool'
complete -c nullray -l splash -d 'Force startup splash'
complete -c nullray -l hide-sensitive -d 'Hide account and API key balances'
complete -c nullray -l list-models -d 'List models for active provider'
complete -c nullray -l completions -d 'Print shell completions' -xa 'bash zsh fish powershell elvish nushell'
complete -c nullray -l man -d 'Print man page source'
