# Skills

Collection of agent skills. Each top-level directory containing a `SKILL.md` is one skill, and the directory name is its ID.

## Install

```bash
./install.sh
```

The script detects the OpenCode skills folder, uses it as the default, and asks where to install. Skills are copied by default; pass `--link` to symlink them to this checkout instead, so edits are live without reinstalling.

```bash
./install.sh --link
./install.sh --path ~/.config/opencode/skills
```

If a skill already exists at the target, the script stops. Pass `--force` to replace it:

```bash
./install.sh --force
```

## Skills

- `code-conventions` — general conventions for any coding or coding-adjacent task, covering tests, comments, commit bodies, PR descriptions, and scope-prefixed commit and PR titles.
