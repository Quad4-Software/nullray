---
name: software-architecture
description: >
  Modern software architecture choices: modular monolith, vertical slices,
  hexagonal ports and adapters, and when to avoid microservice splits. Use when
  designing systems, drawing boundaries, writing ADRs, or reviewing structure.
---

# Software architecture

Load this skill when choosing system shape, drawing module boundaries, or
reviewing whether a change belongs in core, adapters, or a new module.

## Agent workflow

1. State the decision question (deploy split, feature layout, or isolation)
2. Default to a modular monolith unless scale, failure, or ownership forces more
3. Draw capabilities first. Then ports and adapters inside each capability
4. Prefer vertical slices for new features over layer-only folders
5. Write a short ADR for irreversible boundary choices
6. Enforce allowed imports in CI when the repo has package rules

## Layers of decisions

Patterns answer different questions. Do not treat them as rivals.

| Pattern | Question it answers |
|---------|---------------------|
| Modular monolith | How do we split business capabilities in one deployable? |
| Vertical slices | How do we organize a use case end to end? |
| Hexagonal / ports and adapters | How do we keep domain logic free of infrastructure? |
| DDD aggregates | Where do invariants live when rules are complex? |
| Microservices | Which independently deployable units do we need, and why? |

## Default posture

1. Prefer one deployable modular monolith until independent scale, failure
   domains, or team ownership force a split
2. Split by business capability, not by technical layer alone
3. Keep infrastructure behind ports. HTTP, SQL, queues, and vendors are adapters
4. Use vertical slices for features. Keep shared kernels thin
5. Add DDD ceremony only where invariants are non-trivial
6. Write short ADRs for irreversible boundary choices

Detail: [references/patterns.md](references/patterns.md).

## Boundary rules

- Modules talk through public contracts, not shared tables
- Domain code does not import frameworks, ORMs, or UI kits
- New features extend by adding a slice or adapter, not by widening a god service
- Extract a microservice only with a clear ownership, data, and failure story

## Smell checklist

- Cross-module joins or foreign key ownership fights
- Domain types leaking ORM attributes or HTTP DTOs
- "Utils" / "common" packages that every module imports for business rules
- Premature service mesh complexity for a single team and database

## Related skills

- [modular-design](../modular-design/SKILL.md) for file-level modularity and godfiles
- [software-testing](../software-testing/SKILL.md) for test strategy that mirrors boundaries
- [structure](../structure/SKILL.md) for nullray line limits on Odin sources

## Research URLs

Full list: [references/urls.md](references/urls.md).

- Monolith First: https://martinfowler.com/bliki/MonolithFirst.html
- Hexagonal architecture: https://alistair.cockburn.us/hexagonal-architecture/
- ADR site: https://adr.github.io/

