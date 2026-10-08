def "nu-complete nullray flags" [] {
  [
    --help -h --version -V --ephemeral -e --self-test -t
    --audit --doctor --debug --print -P --acp --serve --connect --attach --bare --fail-on-findings
    --provider -p --model -m --theme --mode --perms --gate --sandbox
    --workspace -w --session --list-sessions --search-sessions
    --delete-session --rename-session --force --export-session --import-session --as
    --list-skills --distill --skills
    --keys --message-file --image --audio --video --media --out --plan-out --plan-in
    --output-format --print-strict --auto --usage --timeout --no-splash --no-subagents --splash --hide-sensitive --list-models --completions --man
  ]
}
export extern nullray [
  ...args: string@"nu-complete nullray flags"
]
