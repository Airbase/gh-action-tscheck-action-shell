# no new `@ts-nocheck`

Checks if new `@ts-nocheck` is introduced in a PR or not.

- It looks at `git diff` between the source branch and the destination branch of a pull request
- It identifies `@ts-nocheck` directives in actual TypeScript comments (`//` or `/*`)
- String literals containing `@ts-nocheck` are ignored (e.g., `"@ts-nocheck"`, `'// @ts-nocheck'`, or `` `@ts-nocheck` ``)
- Then, it separates out the additions and deletions and counts the instances of `@ts-nocheck` in each of them
- Finally, it would fail with `exit 1` if the count in additions is more than count in deletions (which would mean the PR has introduced new `@ts-nocheck` instances)

## How it works

The action:
1. Removes all string literals (double quotes, single quotes, and backticks) from each line
2. Searches for `@ts-nocheck` only after comment markers (`//` or `/*`)
3. Compares additions vs. removals to detect new instances

This approach prevents false positives when `@ts-nocheck` appears in strings, while correctly detecting actual TypeScript comment directives.
