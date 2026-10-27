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
default, and prompts for the install path.
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
    cp -R -- "$src" "$target"
  else
    ln -s -- "$src" "$target"
  fi

  printf '  %s -> %s\n' "$name" "$target"
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

printf '\nDone. Restart or reload opencode, then mention @code-conventions to force-load a skill.\n'
