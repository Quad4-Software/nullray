# go echo service

Write `main.go` in this directory (package main, stdlib only) that:

- listens on 127.0.0.1:8799
- `POST /echo` reads the request body and responds 200 with
  `{"echo":"<body>"}` (JSON, Content-Type application/json)
- `GET /health` responds 200 with plain text `ok`
- any other path or method: 404

Build with `go build -o echo main.go`. Do not create a go.mod; the file
must compile with plain `go build`.
