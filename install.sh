#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS=opencode

MODE=copy
DEST=""
FORCE=false

usage() {
  cat <<'EOF'
Install the skills in this repository into an agent harness skills folder.

Usage: ./install.sh [options]

Options:
  --path <dir>   Install into <dir> without prompting.
  --link         Symlink skills instead of copying them.
  --force        Replace existing installs instead of failing.
  -h, --help     Show this help.

With no --path, the script detects the harness skills folder, uses it as the
default, and prompts for the install path. Skills that include an agents/
directory also install those agents into the sibling agents/ folder.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

detect_skills_dir() {
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"

  case "$HARNESS" in
    opencode)
      # Prefer an existing global install, then a project-local folder.
      if [ -d "$xdg/opencode/skills" ]; then
        printf '%s\n' "$xdg/opencode/skills"
        return
      fi

      local root
      if root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" &&
        [ -d "$root/.opencode" ]; then
        printf '%s\n' "$root/.opencode/skills"
        return
      fi

      printf '%s\n' "$xdg/opencode/skills"
      ;;
  esac
}

expand_tilde() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

install_skill() {
  local src="$1" name="$2"
  local target="$DEST/$name"

  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$FORCE" != true ]; then
      die "$target already exists; remove it or pass --force"
    fi
    rm -rf -- "$target"
  fi

  if [ "$MODE" = copy ]; then
    mkdir -p -- "$target"
    (
      cd "$src" || exit 1
      # Agents are installed into the sibling agents/ directory, so omit the
      # nested copy instead of copying it and deleting it afterwards.
      find . -mindepth 1 -maxdepth 1 ! -name agents -exec cp -R {} "$target/" \;
    )
  else
    ln -s -- "$src" "$target"
  fi

  printf '  %s -> %s\n' "$name" "$target"
}

install_agent() {
  local src="$1" name="$2"
  local target="$AGENTS_DEST/$name"

  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$FORCE" != true ]; then
      die "$target already exists; remove it or pass --force"
    fi
    rm -rf -- "$target"
  fi

  if [ "$MODE" = copy ]; then
    cp -- "$src" "$target"
  else
    ln -s -- "$src" "$target"
  fi

  printf '  agents/%s -> %s\n' "$name" "$target"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --path)
      [ "$#" -ge 2 ] || die "--path requires a directory"
      DEST="$2"
      shift 2
      ;;
    --link) MODE=link; shift ;;
    --force) FORCE=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

if ! command -v opencode >/dev/null 2>&1; then
  printf 'warning: opencode not found on PATH; installing anyway\n' >&2
fi

DETECTED="$(detect_skills_dir)"

if [ -n "$DEST" ]; then
  DEST="$(expand_tilde "$DEST")"
elif [ -t 0 ]; then
  printf 'Detected %s skills folder: %s\n' "$HARNESS" "$DETECTED"
  printf 'Install path [%s]: ' "$DETECTED"
  IFS= read -r answer || answer=""
  DEST="$(expand_tilde "${answer:-$DETECTED}")"
else
  die "no --path given and no terminal to prompt on (use --path)"
fi

[ -n "$DEST" ] || die "install path is empty"
AGENTS_DEST="$(dirname "$DEST")/agents"
mkdir -p -- "$DEST"

printf 'Installing skills from %s into %s\n' "$REPO_DIR" "$DEST"

found=0
for skill_md in "$REPO_DIR"/*/SKILL.md; do
  [ -e "$skill_md" ] || continue
  src="$(dirname "$skill_md")"
  install_skill "$src" "$(basename "$src")"
  found=1
done

[ "$found" = 1 ] || die "no skills found in $REPO_DIR"

found_agents=0
for agent_md in "$REPO_DIR"/*/agents/*.md; do
  [ -e "$agent_md" ] || continue
  mkdir -p -- "$AGENTS_DEST"
  install_agent "$agent_md" "$(basename "$agent_md")"
  found_agents=1
done

if [ "$found_agents" = 0 ]; then
  printf '  no agents to install\n'
fi

printf '\nDone. Restart or reload opencode, then mention a skill ID to force-load it.\n'
