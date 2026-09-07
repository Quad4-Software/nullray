use str
set edit:completion:arg-completer[nullray] = {|@args|
  var flags = [
    --help -h --version -V --ephemeral -e --self-test -t
    --audit --doctor --debug --print -P --bare --fail-on-findings
    --provider -p --model -m --theme --mode --perms --sandbox
    --workspace -w --session --list-sessions --search-sessions
    --delete-session --export-session --import-session --as
    --list-skills --install-skill --uninstall-skill --skills
    --keys --message-file --out --plan-out --plan-in
    --output-format --print-strict --auto --usage --timeout --no-splash --no-subagents --splash --hide-sensitive --list-models --completions --man
  ]
  put $@flags
}
