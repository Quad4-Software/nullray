# Wails v3 services and events

## Services

Services are plain Go types. Inject the app instance explicitly when needed.
Exported methods become callable from the frontend after generation.

Errors from Go methods surface as rejected promises / thrown errors in JS.

## Events

```
app.Event.On("name", handler)
app.Event.Emit("name", data)
```

Use typed registration APIs when you need TypeScript-safe payloads. Hooks can
cancel certain lifecycle events (for example confirm-before-close).

## Build

Customize Taskfile targets rather than fighting a black-box builder. Icon and
manifest helpers live as CLI tools composed by tasks.
