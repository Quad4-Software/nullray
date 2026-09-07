use str
set edit:completion:arg-completer[nullray] = {|@args|
  var flags = [
    --help -h --version -V --ephemeral -e --self-test -t
    --provider -p --model -m --theme --mode --perms --sandbox
    --workspace -w --session --list-models --completions --man
  ]
  put $@flags
}
