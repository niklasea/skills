---
name: code-conventions
description: Apply code conventions to any coding or coding-adjacent task, including implementation, bug fixes, refactoring, tests, linting/formatting, dependency updates, build tooling, CI/CD, file and diff review, commits, and pull requests. Always use when writing or changing code, config, or automation, and when reviewing code.
---

# Code Conventions

These conventions apply to every coding or coding-adjacent task, including CI/CD, build scripts, and dependency updates.

## General

- Match the conventions already in use in the repository you are working in.
- Keep each commit and pull request focused on one scope; split unrelated work. For large projects, split the work into features and stack dependant pull requests.
- Never change commit history without direct user approval, including to fix branch names, commit prefixes, or commit bodies.
- If a flaw is discovered in a commit that has already been pushed to the remote, the fix should come through a new commit, not by rewriting history.
- Prefer a generic solution if it does not complicate the code needlessly.
- Always work in a separate git worktree branched of `origin/main` unless told otherwise.

## Permissions

- Do not speak on the user's behalf, for example by posting pull request comments.
- Never close a pull request without explicit permission. If it needs a complete redo, rework the existing pull request instead of closing it and starting over.

## Testing

- Prefer parameterised tests over separate tests per case.
- Never add tests for UI formatting; rely on visual confirmation by the user.

## Code comments

Code should generally default to no comments; the code should document itself and what is being done through clear naming.

Docstrings should focus on *what* the class/function is for, its inputs, and its outputs.
Public interfaces always get docstrings.

In-code comments should always explain *why* something is done, or done in that particular way.
The only exception is when the code is particularly hard to reason about: complex regex, bit manipulation.

A comment must state both the concrete failure mode it prevents and the invariant or requirement it protects. Do not describe the mechanism; the code shows that. Keep it to one line, e.g. `root:root nodes break later deploys; config nodes must be group vyattacfg`, not `writes require the vyattacfg group`.

Comments should never contain config literals, e.g. never `retries every 3 seconds`, rather something like `retries with a set interval`.

## Creating a PR

When creating a PR, have a subagent review the code and fix any findings that have merit. Mark the PR ready for review only after the review process.
Clean up after yourself in the local worktree once the PR is on the remote and ready for review.

## Commit and PR titles

Prefix every commit subject and pull request title with the area being changed:

```
<scope>: <imperative summary>
```

Examples:

- `API: add cursor pagination to /users`
- `CI: cache pnpm store between jobs`
- `Docs: correct the install command`

Use the narrowest accurate scope: a package, directory, or subsystem. Keep the summary imperative and lowercase, with no trailing period.

Do not use a type prefix in place of a scope. `feat:`, `fix:`, and `chore:` do not satisfy this rule, and `feat(api):` is type-first rather than scope-first.

## Commit body

List each change with a short description. If the reason for the change is not obvious from the description, add a short paragraph explaining why.

## PR body

The PR description should either follow the in-repository template or the following template:

```
# Motivation

<Short summary of the PR and why it exists. Keep under 200 words>

# Changes

<List each change with a short description of the change and why it was made. Keep under 50 words per change>

- <Change 1>
- <Change 2>
- <Change 3>

# Pre-merge

<Any prerequisite manual steps before merge. This section is optional, omit if there are none>

# Post-merge

<Any prerequisite manual steps to take after merge. This section is optional, omit if there are none>
```
