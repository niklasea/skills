# Skills

Collection of agent skills. Each top-level directory containing a `SKILL.md` is one skill, and the directory name is its ID.

## Install

```bash
./install.sh
```

The script detects the OpenCode skills folder, uses it as the default, and asks where to install. Skills are copied by default; pass `--link` to symlink them to this checkout instead, so edits are live without reinstalling. Agent definitions live in the top-level `agents/` directory and are installed into the `agents/` directory next to the skills directory.

```bash
./install.sh --link
./install.sh --path ~/.config/opencode/skills
```

If a skill already exists at the target, the script stops. Pass `--force` to replace it:

```bash
./install.sh --force
```

## Global instructions

`global/AGENTS.md` contains agent-behaviour rules that apply to every task, not only coding work. From the repository root, install it as your global OpenCode instructions so it loads in every session:

```bash
target="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md"
mkdir -p "$(dirname "$target")"
if [ -L "$target" ]; then rm -- "$target"; fi
ln -s "$PWD/global/AGENTS.md" "$target"
```

If you already have a global `AGENTS.md` file, merge the rules into it instead; the command replaces only an existing symlink. Re-run it if you move this checkout, since the link points at its current location. The `code-conventions` skill assumes these rules are installed; it only covers coding-related guidance.

## Skills

- `code-conventions` — conventions for any coding or coding-adjacent task, covering tests, comments, commit bodies, PR descriptions, and scope-prefixed commit and PR titles.
- `code-review` — reviews changes with independent language lanes, adversarial refutation, and confirmation-gated fixes.
