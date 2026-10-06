# Go generic methods

Official walkthrough: https://go.dev/blog/generic-methods
Release notes: https://go.dev/doc/go1.27

## Why

Before 1.27, type parameters lived on package-level functions. Methods on a
concrete type could not declare their own type parameters. That forced awkward
helpers like `MapList(list, f)` instead of `list.Map(f)`.

## Allowed

```go
type List[E any] []E

func (l List[E]) Map[R any](f func(E) R) List[R] {
	out := make(List[R], len(l))
	for i, v := range l {
		out[i] = f(v)
	}
	return out
}
```

Instantiate explicitly or via inference:

```go
doubled := list.Map(func(x int) int { return x * 2 })
```

Method expressions still work: `List[int].Map[string]`.

## Not allowed

- Interface methods with type parameters
- Using a generic method as the implementation of an interface method

If callers need an interface, keep a non-generic method set and put generics on
package funcs or on concrete helpers that return interface values.

## Inference expansion

Generic functions can be used without type args wherever assigned to a matching
function type: composite literal elements, conversions, and channel sends.
