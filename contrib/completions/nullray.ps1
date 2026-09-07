Register-ArgumentCompleter -CommandName nullray -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  $opts = @(
    '--help','-h','--version','-V','--ephemeral','-e','--self-test','-t',
    '--provider','-p','--model','-m','--theme','--mode','--perms','--sandbox',
    '--workspace','-w','--session','--list-models','--completions','--man'
  )
  $opts | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
  }
}
