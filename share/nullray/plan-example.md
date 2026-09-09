## Goal
Add a list_dir smoke test.

## Scope
nullray/tools tests only.

## Steps
1. Read existing list_dir tests.
2. Add one failing case for an empty path.
3. Run make test and fix until green.

## Risks
Sandbox workspace override in tests.

## Verify
make test

## Success
New test passes in the tools package.

## Budget
4

## Failure
Same failure twice after a fix attempt.
