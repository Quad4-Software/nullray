#compdef nullray
_nullray() {
  local -a opts providers modes perms sandboxes shells themes
  opts=(
    '--help[show help]' '-h[show help]'
    '--version[show version]' '-V[show version]'
    '--ephemeral[do not load or save transcripts]' '-e[do not load or save transcripts]'
    '--self-test[headless smoke]' '-t[headless smoke]'
    '--provider[provider id]:provider:(ollama lmstudio openai openai-compat openrouter opencode opencode-go)'
    '-p[provider id]:provider:(ollama lmstudio openai openai-compat openrouter opencode opencode-go)'
    '--model[model id]:model:'
    '-m[model id]:model:'
    '--theme[ui theme]:theme:(ink ember moss slate rose mono dusk)'
    '--mode[agent mode]:mode:(ask plan edit)'
    '--perms[shell policy]:perms:(ask allow yolo)'
    '--sandbox[sandbox mode]:sandbox:(on off landlock seccomp)'
    '--workspace[workspace path]:dir:_files -/'
    '-w[workspace path]:dir:_files -/'
    '--session[session name]:session:'
    '--list-models[list models for active provider]'
    '--completions[print shell completions]:shell:(bash zsh fish powershell elvish nushell)'
    '--man[print man page source]'
  )
  _arguments -s : $opts
}
compdef _nullray nullray
