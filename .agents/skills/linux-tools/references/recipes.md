# Linux tool recipes

## Search

```
rg -n 'pattern' path
rg --files -g '*.odin'
fd -e odin sandbox
find . -name '*.odin' -print
```

## HTTP debug

```
curl -fsSL -D- -o /tmp/body "https://example.com"
curl -fsS -X POST -H 'content-type: application/json' -d '{"a":1}' URL
```

## JSON

```
jq '.key' file.json
jq -r '.items[].name' file.json
```

## Network

```
ss -lntp
ip -br addr
ip route
dig +short example.com
```

## systemd

```
systemctl status UNIT
systemctl --user status UNIT
journalctl -u UNIT -n 100 --no-pager
journalctl --since '1 hour ago' -u UNIT
```

## Permissions

```
ls -la path
stat path
chmod u+x script.sh
# avoid chmod -R 777
```

## Disk and process

```
df -h
du -sh *
ps aux | rg processname
```

## Archives

```
tar -tzf archive.tgz | head
tar -xzf archive.tgz -C dest
```

Inspect untrusted archives before extract. Watch for path traversal entries.
