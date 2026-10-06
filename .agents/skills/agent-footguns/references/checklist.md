# Agent self-check checklist

Copy and track:

```
- [ ] Read existing code and skills before writing
- [ ] Confirmed versions from package manifests or docs URLs
- [ ] Changes limited to requested scope
- [ ] No secrets in files, commits, or logs
- [ ] Verify command run (or explicitly blocked)
- [ ] Public APIs unchanged unless required
- [ ] Destructive ops approved by user
- [ ] Summarized with real paths and outcomes
```

## Review questions for agent output

1. Would this compile or typecheck in the real tree
2. Did the agent invent a symbol that does not exist
3. Are tests asserting behavior or only mocking
4. Is the diff minimal
5. Can a human reverse the change easily
