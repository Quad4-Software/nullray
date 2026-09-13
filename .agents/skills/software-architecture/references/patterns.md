# Architecture pattern notes

## Modular monolith

One binary or service process. Multiple modules with enforced boundaries.

Each module owns:

- Its use cases / slices
- Its domain model (as needed)
- Its adapters (persistence, messaging, UI entry)
- A small public contract other modules may call

Do not share another module's tables as an API. Ask through a contract or emit
an event the owning module defines.

## Vertical slices

Organize by feature: create-order, cancel-order, list-orders. A slice contains
the handler, validation, and persistence calls for that use case. Prefer this
over scattering one feature across Controller / Service / Repository folders
that hide the flow.

Combine with Clean / hexagonal ideas by keeping domain decisions inward while
still colocating the feature's wiring.

## Hexagonal (ports and adapters)

Inside: application and domain. Outside: drivers (HTTP, CLI, jobs) and driven
adapters (DB, mail, third parties).

Ports are interfaces owned by the inside. Adapters implement or call those
ports. The point is substitutability for tests and for swapping vendors, not
drawing a hexagon with exactly six sides.

Skip ports for stable one-off details that will never change. Ceremony without
a second adapter is noise.

## DDD, lightly

Use aggregates and value objects where invariants must hold together. Do not
force aggregates onto CRUD screens. Do not turn aggregates into service
locators that reach other modules or the network.

## Microservices later

Split when you need independent deploy cadence, scaling, or failure isolation
that a modular monolith cannot give. Keep the module contract as the future
service API. Do not split solely because folders exist.

## Architecture tests

Enforce allowed dependencies with tooling (package rules, import linters,
ArchUnit-style tests). Documentation alone drifts. Fail CI when a module
imports another module's internals.
