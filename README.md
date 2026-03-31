# no new `@ts-nocheck`

Checks if new `@ts-nocheck` is introduced in a PR or not.

- It compares the pull request's current `HEAD` against the merge-base with the destination branch
- It searches for the patterns `// @ts-nocheck` or `/* @ts-nocheck` in added/removed lines
- Then, it separates out the additions and deletions and counts the instances in each of them
- Finally, it would fail with `exit 1` if the count in additions is more than count in deletions (which would mean the PR has introduced new `@ts-nocheck` instances)

## How it works

The action searches for lines containing either:
- `// @ts-nocheck` - line comment pattern
- `/* @ts-nocheck` - block comment pattern

Lines can have other content before or after these patterns. The check ignores plain `@ts-nocheck` without comment markers.

The action fetches the base branch ref it needs before computing the merge-base, which avoids false positives when the PR branch is behind the base branch.

## Tests

Run the regression tests locally with:

```bash
node tests/diff_test.ts
```
