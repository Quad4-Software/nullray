Register-ArgumentCompleter -CommandName nullray -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  $opts = @(
    '--help','-h','--version','-V','--ephemeral','-e','--self-test','-t',
    '--audit','--doctor','--debug','--print','-P','--bare','--fail-on-findings',
    '--provider','-p','--model','-m','--theme','--mode','--perms','--sandbox',
    '--workspace','-w','--session','--list-sessions','--search-sessions',
    '--delete-session','--export-session','--import-session','--as',
    '--list-skills','--install-skill','--uninstall-skill','--skills',
    '--keys','--message-file','--out','--plan-out','--plan-in',
    '--output-format','--print-strict','--auto','--usage','--timeout','--no-splash','--no-subagents','--splash','--hide-sensitive','--list-models','--completions','--man'
  )
  $opts | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
  }
}
