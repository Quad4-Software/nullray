# Dotfiles layout

Short tree for a user config repo synced into `~/.config` or `$XDG_CONFIG_HOME`.

```
dotfiles/
  README.md
  install.sh          # idempotent symlinks or copies into $HOME
  config/
    nullray/
      env
      keys.ini
    shell/
      profile snippet
    app/
      app-specific config
```

Keep secrets out of the repo. Use env files listed in `.gitignore` or a host credential store. Run `install.sh` from the repo root after clone.
