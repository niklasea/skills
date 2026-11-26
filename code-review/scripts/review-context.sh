#!/usr/bin/env bash
#
# Collect review context for the code-review skill.
# Usage: review-context.sh [git-revision-or-range]
#
# A single revision is the base to diff against the working tree, so branch
# commits and uncommitted changes are both included. Use A..B for a commit-only
# range, or A^..A to review one commit.
#
# Writes to /tmp/opencode/review-<sha>/ by default. Override with REVIEW_OUT_DIR.

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "not inside a git repository" >&2
  exit 2
}
cd "$repo_root"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required" >&2
  exit 2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

validate_range() {
  local spec="$1" left right
  [ -n "$spec" ] || return 1
  case "$spec" in
    *..*)
      left="${spec%%..*}"
      right="${spec#*..}"
      if [ "${right#.}" != "$right" ]; then
        right="${right#.}"
      fi
      [ -n "$left" ] || left="HEAD"
      [ -n "$right" ] || right="HEAD"
      git rev-parse --verify --quiet "${left}^{commit}" >/dev/null 2>&1 || return 1
      git rev-parse --verify --quiet "${right}^{commit}" >/dev/null 2>&1 || return 1
      ;;
    *)
      git rev-parse --verify --quiet "${spec}^{commit}" >/dev/null 2>&1 || return 1
      ;;
  esac
  return 0
}

range="${1:-}"
worktree_included=1
if [ -z "$range" ]; then
  if git rev-parse --verify -q origin/main >/dev/null 2>&1; then
    # Diff from the merge base to the working tree, so branch commits,
    # staged changes, and unstaged changes are all included.
    range="$(git merge-base origin/main HEAD)" ||
      die "cannot find a merge base between origin/main and HEAD"
    [ -n "$range" ] || die "cannot find a merge base between origin/main and HEAD"
  else
    range="HEAD"
  fi
else
  case "$range" in
    *..*) worktree_included=0 ;;
  esac
fi

short=$(git rev-parse --short=12 HEAD 2>/dev/null || echo "nogit")
out="${REVIEW_OUT_DIR:-/tmp/opencode/review-$short}"
mkdir -p "$out"

# Clear prior artifacts so a failed run cannot leave a stale patch for a lane.
: >"$out/diff.patch"
: >"$out/untracked.patch"
: >"$out/changed-files.txt"
: >"$out/diff.stat"
: >"$out/untracked.txt"
: >"$out/status.txt"
: >"$out/recent-commits.txt"
rm -f -- "$out/.untracked.raw"

validate_range "$range" || die "not a valid revision or range: $range"

if [ "$worktree_included" = 1 ]; then
  reviewed_upper="worktree"
  base_rev="$range"
else
  reviewed_upper="${range#*..}"
  if [ "${reviewed_upper#.}" != "$reviewed_upper" ]; then
    reviewed_upper="${reviewed_upper#.}"
  fi
  [ -n "$reviewed_upper" ] || reviewed_upper="HEAD"
  reviewed_upper="$(git rev-parse --verify "${reviewed_upper}^{commit}")" ||
    die "cannot resolve the upper bound of '$range'"
  base_rev="${range%%..*}"
  [ -n "$base_rev" ] || base_rev="HEAD"
fi

git diff --no-ext-diff --unified=80 "$range" >"$out/diff.patch" 2>"$out/diff.err" || {
  cat "$out/diff.err" >&2
  die "cannot compute diff for '$range'"
}
git diff --name-status "$range" >"$out/changed-files.txt" 2>"$out/diff.err" || {
  cat "$out/diff.err" >&2
  die "cannot list changed files for '$range'"
}
git diff --stat "$range" >"$out/diff.stat" 2>"$out/diff.err" || {
  cat "$out/diff.err" >&2
  die "cannot compute diff stat for '$range'"
}
git status --porcelain=v1 >"$out/status.txt" 2>/dev/null || true
git log --oneline -20 >"$out/recent-commits.txt" 2>/dev/null || true

if [ "$worktree_included" = 1 ]; then
  raw_untracked="$out/.untracked.raw"
  git ls-files --others --exclude-standard >"$raw_untracked" 2>"$out/diff.err" ||
    die "cannot list untracked files"
  if [ "${REVIEW_INCLUDE_PACK:-0}" = "1" ]; then
    cp -- "$raw_untracked" "$out/untracked.txt"
  else
    grep -v -E '^(\.opencode/|node_modules/|target/|bin/|obj/|\.terraform/|__pycache__/)' \
      "$raw_untracked" >"$out/untracked.txt" || true
  fi
  rm -f -- "$raw_untracked"

  if [ -s "$out/untracked.txt" ]; then
    while IFS= read -r file; do
      [ -f "$file" ] || continue
      git diff --no-index --unified=40 -- /dev/null "$file" >>"$out/untracked.patch" 2>/dev/null || true
    done <"$out/untracked.txt"
  fi
fi

python3 - "$repo_root" "$range" "$out" "$base_rev" "$reviewed_upper" "$worktree_included" <<'PY'
import datetime
import json
import os
import subprocess
import sys

repo_root, range_arg, out, base_arg, reviewed_upper, worktree_flag = sys.argv[1:7]


def lines(name):
    path = os.path.join(out, name)
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return [line.rstrip("\n") for line in handle if line.strip()]
    except FileNotFoundError:
        return []


def git(*args):
    try:
        return subprocess.check_output(
            ["git", *args], cwd=repo_root, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        return None


changed = lines("changed-files.txt")
changed_paths = []
for entry in changed:
    parts = entry.split("\t")
    if len(parts) >= 2:
        changed_paths.append(parts[-1])

meta = {
    "repo_root": repo_root,
    "range": range_arg,
    "head": git("rev-parse", "HEAD"),
    "base": git("rev-parse", f"{base_arg}^{{commit}}") or base_arg,
    "reviewed_upper": reviewed_upper,
    "worktree_included": worktree_flag == "1",
    "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "out_dir": out,
    "diff": os.path.join(out, "diff.patch"),
    "untracked_patch": os.path.join(out, "untracked.patch"),
    "changed_files": changed,
    "changed_paths": changed_paths,
    "untracked_files": lines("untracked.txt"),
    "status": lines("status.txt"),
    "recent_commits": lines("recent-commits.txt"),
}

with open(os.path.join(out, "context.json"), "w", encoding="utf-8") as handle:
    json.dump(meta, handle, indent=2)
    handle.write("\n")

print(json.dumps(meta, indent=2))
PY
