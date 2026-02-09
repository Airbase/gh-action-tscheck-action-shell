# no new `@ts-nocheck`

Checks if new `@ts-nocheck` is introduced in a PR or not.

- It looks at `git diff` between the source branch and the destination branch of a pull request
- It searches for the patterns `// @ts-nocheck` or `/* @ts-nocheck` in added/removed lines
- Then, it separates out the additions and deletions and counts the instances in each of them
- Finally, it would fail with `exit 1` if the count in additions is more than count in deletions (which would mean the PR has introduced new `@ts-nocheck` instances)

## How it works

The action searches for lines containing either:
- `// @ts-nocheck` - line comment pattern
- `/* @ts-nocheck` - block comment pattern

Lines can have other content before or after these patterns. The check ignores plain `@ts-nocheck` without comment markers.
