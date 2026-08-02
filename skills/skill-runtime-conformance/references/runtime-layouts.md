# Runtime layouts

The version 1 manifest is repository-relative:

```json
{
  "version": 1,
  "canonical": ".claude/skills",
  "published": ["example-skill"],
  "targets": {
    "codex": {"path": ".agents/skills", "format": "directory"},
    "opencode": {"path": ".opencode/skills", "format": "directory"},
    "cursor": {"path": ".cursor/rules", "format": "cursor-rule"}
  }
}
```

- `directory` targets must contain a byte-identical skill directory.
- `cursor-rule` targets use `<skill>.mdc`. The audit checks the generator marker, source pointer, and canonical skill body because Cursor frontmatter differs.
- `published` is the only publication authority. Generated output not listed there is an orphan only when it bears the generator marker.
- Keep runtime-specific transformation in the repository generator. The audit is read-only.
