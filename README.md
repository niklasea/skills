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

## Global instructions

`global/AGENTS.md` contains agent-behaviour rules that apply to every task, not only coding work. Install it as your global OpenCode instructions so it loads on every session:

```bash
ln -s "$PWD/global/AGENTS.md" ~/.config/opencode/AGENTS.md
```

If you already have a global `AGENTS.md`, merge the rules into it instead. The `code-conventions` skill assumes these rules are installed; it only covers coding conventions.

## Skills

- `code-conventions` — conventions for any coding or coding-adjacent task, covering tests, comments, commit bodies, PR descriptions, and scope-prefixed commit and PR titles.
