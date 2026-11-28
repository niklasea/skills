---
name: code-conventions
description: Apply code conventions to any coding or coding-adjacent task, including implementation, bug fixes, refactoring, tests, linting/formatting, dependency updates, build tooling, CI/CD, file and diff review, commits, and pull requests. Always use when planning, writing, or changing code, config, infrastructure, network configuration, or automation, when reviewing code, or whenever the work will result in a commit or pull request.
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

## Migrations

- Do not add application code that exists only to run a one-time migration and will be dead once the migration is complete. Put the manual steps in the pull request's pre-/post-merge section, as the timing requires, or the equivalent section of the repository's template. Tool-managed migration files that the repository keeps and applies automatically are exempt.
- If such code is unavoidable, open a follow-up pull request that removes it once the migration is complete. Base its branch on this pull request's branch if this one is still open; otherwise base it on the default branch.

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
They should name the concrete failure mode they prevent and the invariant or requirement they protect, not the mechanism, which the code already shows. E.g. `deploys break after an ownership change; config nodes must stay writable by the config daemon`, not `writes require the config daemon's group`.
Keep comments concise: one short sentence is usually enough.

The only exception is when the code is particularly hard to reason about: complex regex, bit manipulation.

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
