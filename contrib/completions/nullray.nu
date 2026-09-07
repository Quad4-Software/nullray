def "nu-complete nullray flags" [] {
  [
    --help -h --version -V --ephemeral -e --self-test -t
    --provider -p --model -m --theme --mode --perms --sandbox
    --workspace -w --session --list-models --completions --man
  ]
}
export extern nullray [
  ...args: string@"nu-complete nullray flags"
]
