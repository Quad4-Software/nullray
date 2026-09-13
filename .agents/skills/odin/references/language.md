# Odin language notes

Overview: https://odin-lang.org/docs/overview/

This file is a workspace cheat sheet. Prefer the official overview when syntax
details conflict.

## Packages

- One package name per directory
- Files in a directory share the package
- Collections map import paths (`nullray:sandbox`) to trees on disk

## Context and allocators

```
context.allocator       long-lived owned memory
context.temp_allocator  scratch for the current scope / frame
```

APIs that return owned strings must document who frees them. Clone before
storing past the callee. Do not return slices into stack arrays.

## Errors

Common local style: `(value, err: string)` with empty `err` meaning success.
Match the package you are editing. Do not invent a new error enum without a
repo convention.

## Build tags

```
#+build linux
#+build windows
#+build darwin
```

Put platform code in dedicated files. Keep shared logic tag-free when possible.

## Tests

```
odin test <package> -define:ODIN_TEST_THREADS=1
```

This repo's `make test` sets that define. Prefer it for reproducibility.

## Unsafe edges

- Integer casts truncate. Validate wire sizes
- FFI must match C layout and lifetime
- Bounds checks exist. Do not disable them without measurement and review

Pair with [odin-idioms](../../odin-idioms/SKILL.md) and [memory](../../memory/SKILL.md)
for nullray ownership rules.
