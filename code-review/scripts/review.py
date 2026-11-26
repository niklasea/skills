#!/usr/bin/env python3
"""Collect review context or run the deterministic review gate."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

GIT = "git"


def die(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(2)


def git(args, repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE):
    return subprocess.run(
        [GIT, *args],
        cwd=repo,
        stdout=stdout,
        stderr=stderr,
        text=True,
        errors="replace",
    )


def git_output(args, repo):
    try:
        result = git(args, repo)
    except FileNotFoundError:
        die("git is required")
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def git_ok(args, repo):
    try:
        result = git(args, repo, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        die("git is required")
    return result.returncode == 0


def repo_root():
    if shutil.which(GIT) is None:
        die("git is required")
    result = git(["rev-parse", "--show-toplevel"], None)
    if result.returncode != 0:
        die("not inside a git repository")
    return result.stdout.strip()


def validate_range(repo, spec):
    if not spec:
        return False
    if ".." in spec:
        left, right = spec.split("..", 1)
        if right.startswith("."):
            right = right[1:]
        left = left or "HEAD"
        right = right or "HEAD"
        return git_ok(
            ["rev-parse", "--verify", "--quiet", f"{left}^{{commit}}"], repo
        ) and git_ok(
            ["rev-parse", "--verify", "--quiet", f"{right}^{{commit}}"], repo
        )
    return git_ok(["rev-parse", "--verify", "--quiet", f"{spec}^{{commit}}"], repo)


def resolve_input_range(repo, spec):
    if spec:
        return spec, ".." not in spec
    if git_ok(["rev-parse", "--verify", "-q", "origin/main"], repo):
        range_arg = git_output(["merge-base", "origin/main", "HEAD"], repo)
        if not range_arg:
            die("cannot find a merge base between origin/main and HEAD")
        return range_arg, True
    return "HEAD", True


def reviewed_bounds(repo, range_arg, worktree_included):
    if worktree_included:
        return range_arg, "worktree"

    left, right = range_arg.split("..", 1)
    if right.startswith("."):
        right = right[1:]
    right = right or "HEAD"
    reviewed_upper = git_output(["rev-parse", "--verify", f"{right}^{{commit}}"], repo)
    if not reviewed_upper:
        die(f"cannot resolve the upper bound of '{range_arg}'")
    return left or "HEAD", reviewed_upper


def default_out(repo):
    short = git_output(["rev-parse", "--short=12", "HEAD"], repo) or "nogit"
    return Path(os.environ.get("REVIEW_OUT_DIR") or f"/tmp/opencode/review-{short}")


def read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return [line.rstrip("\n") for line in handle if line.strip()]
    except FileNotFoundError:
        return []


def write_git_file(repo, args, path, error_path, message):
    with open(path, "w", encoding="utf-8") as handle:
        result = git(args, repo, stdout=handle, stderr=subprocess.PIPE)
    with open(error_path, "w", encoding="utf-8") as error:
        error.write(result.stderr or "")
    if result.returncode != 0:
        if result.stderr:
            sys.stderr.write(result.stderr)
        die(message)


def run_context(repo, spec):
    os.chdir(repo)
    range_arg, worktree_included = resolve_input_range(repo, spec)
    out = default_out(repo)
    out.mkdir(parents=True, exist_ok=True)

    for name in (
        "diff.patch",
        "untracked.patch",
        "changed-files.txt",
        "diff.stat",
        "untracked.txt",
        "status.txt",
        "recent-commits.txt",
        "diff.err",
    ):
        (out / name).write_text("", encoding="utf-8")
    try:
        (out / ".untracked.raw").unlink()
    except FileNotFoundError:
        pass

    if not validate_range(repo, range_arg):
        die(f"not a valid revision or range: {range_arg}")
    base_rev, reviewed_upper = reviewed_bounds(repo, range_arg, worktree_included)

    write_git_file(
        repo,
        ["diff", "--no-ext-diff", "--unified=80", range_arg],
        out / "diff.patch",
        out / "diff.err",
        f"cannot compute diff for '{range_arg}'",
    )
    write_git_file(
        repo,
        ["diff", "--name-status", range_arg],
        out / "changed-files.txt",
        out / "diff.err",
        f"cannot list changed files for '{range_arg}'",
    )
    write_git_file(
        repo,
        ["diff", "--stat", range_arg],
        out / "diff.stat",
        out / "diff.err",
        f"cannot compute diff stat for '{range_arg}'",
    )

    status = git(["status", "--porcelain=v1"], repo)
    (out / "status.txt").write_text(
        status.stdout if status.returncode == 0 else "", encoding="utf-8"
    )
    commits = git(["log", "--oneline", "-20"], repo)
    (out / "recent-commits.txt").write_text(
        commits.stdout if commits.returncode == 0 else "", encoding="utf-8"
    )

    if worktree_included:
        listed = git(["ls-files", "-z", "--others", "--exclude-standard"], repo)
        if listed.returncode != 0:
            die("cannot list untracked files")
        untracked = [path for path in listed.stdout.split("\0") if path]
        if os.environ.get("REVIEW_INCLUDE_PACK") != "1":
            ignored = re.compile(
                r"^(\.opencode/|node_modules/|target/|bin/|obj/|\.terraform/|__pycache__/)"
            )
            untracked = [path for path in untracked if not ignored.match(path)]
        (out / "untracked.txt").write_text(
            "".join(f"{path}\n" for path in untracked), encoding="utf-8"
        )
        if untracked:
            with open(out / "untracked.patch", "a", encoding="utf-8") as handle:
                for path in untracked:
                    if not os.path.isfile(os.path.join(repo, path)):
                        continue
                    git(
                        ["diff", "--no-index", "--unified=40", "--", "/dev/null", path],
                        repo,
                        stdout=handle,
                        stderr=subprocess.DEVNULL,
                    )

    changed = read_lines(out / "changed-files.txt")
    changed_paths = []
    for entry in changed:
        parts = entry.split("\t")
        if len(parts) >= 2:
            changed_paths.append(parts[-1])

    meta = {
        "repo_root": repo,
        "range": range_arg,
        "head": git_output(["rev-parse", "HEAD"], repo),
        "base": git_output(["rev-parse", f"{base_rev}^{{commit}}"], repo) or base_rev,
        "reviewed_upper": reviewed_upper,
        "worktree_included": worktree_included,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "out_dir": str(out),
        "diff": str(out / "diff.patch"),
        "untracked_patch": str(out / "untracked.patch"),
        "changed_files": changed,
        "changed_paths": changed_paths,
        "untracked_files": read_lines(out / "untracked.txt"),
        "status": read_lines(out / "status.txt"),
        "recent_commits": read_lines(out / "recent-commits.txt"),
    }

    with open(out / "context.json", "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2)
        handle.write("\n")
    print(json.dumps(meta, indent=2))
    return 0


def iter_repo_files():
    for root, dirs, files in os.walk("."):
        dirs[:] = [name for name in dirs if name != ".git"]
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            yield path


def run_gate(repo, spec):
    os.chdir(repo)
    out = default_out(repo)
    out.mkdir(parents=True, exist_ok=True)
    log_path = out / "gate.log"
    log = open(log_path, "w", encoding="utf-8", errors="replace")
    counts = {"pass": 0, "fail": 0, "skip": 0}

    def record(status, name, detail):
        line = f"{name:<28} {status:<6} {detail}"
        print(line)
        log.write(line + "\n")
        log.flush()
        if status in counts:
            counts[status] += 1

    def have(tool):
        return shutil.which(tool) is not None

    def run_cmd(args):
        log.flush()
        try:
            result = subprocess.run(
                args,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=180,
            )
            return result.returncode
        except subprocess.TimeoutExpired:
            return 124
        except FileNotFoundError:
            return 127
        except OSError:
            return 126
        finally:
            log.flush()

    def run(name, *args):
        if not args:
            record("skip", name, "no command")
            return
        tool = args[0]
        if not have(tool):
            record("skip", name, f"missing {tool}")
            return
        code = run_cmd(list(args))
        if code == 0:
            record("pass", name, " ".join(args))
        else:
            record("fail", name, f"exit {code}: {' '.join(args)}")

    if spec:
        range_arg = spec
    elif git_ok(["rev-parse", "--verify", "-q", "origin/main"], repo):
        range_arg = git_output(["merge-base", "origin/main", "HEAD"], repo)
        if not range_arg:
            print(
                "error: cannot find a merge base between origin/main and HEAD",
                file=sys.stderr,
            )
            log.close()
            return 2
    else:
        range_arg = "HEAD"

    if not validate_range(repo, range_arg):
        print(f"error: not a valid revision or range: {range_arg}", file=sys.stderr)
        line = f"{'git-diff-check':<28} {'fatal':<6} invalid range: {range_arg}"
        print(line)
        log.write(line + "\n")
        log.close()
        return 2

    record("header", "gate", f"repository: {repo}")
    record("header", "gate", f"output: {out}")

    checked = git(["diff", "--check", range_arg], repo, stderr=subprocess.STDOUT)
    log.write(checked.stdout or "")
    if not (checked.stdout or "").endswith("\n"):
        log.write("\n")
    log.flush()
    if checked.returncode == 0:
        record("pass", "git-diff-check", "no whitespace errors")
    elif checked.returncode == 2:
        record("fail", "git-diff-check", "whitespace errors or conflict markers")
    else:
        print(
            f"error: cannot diff {range_arg} (exit {checked.returncode})",
            file=sys.stderr,
        )
        record(
            "fail",
            "git-diff-check",
            f"cannot diff '{range_arg}' (exit {checked.returncode})",
        )
        log.close()
        return 2

    if Path("terraform").is_dir():
        run("terraform-fmt", "terraform", "fmt", "-check", "-recursive", "terraform")
        if Path("terraform/.terraform").is_dir():
            run(
                "terraform-validate",
                "terraform",
                "-chdir=terraform",
                "validate",
                "-no-color",
            )
        else:
            record(
                "skip",
                "terraform-validate",
                "terraform/.terraform missing; run terraform init -backend=false",
            )
        run("tflint", "tflint", "--chdir=terraform")
        run("checkov", "checkov", "-d", "terraform", "--compact")
    else:
        record("skip", "terraform", "no terraform/ directory")

    if Path("ansible").is_dir():
        if Path(".github/linters/.ansible-lint.yml").is_file():
            run(
                "ansible-lint",
                "ansible-lint",
                "-c",
                ".github/linters/.ansible-lint.yml",
                "ansible",
            )
        else:
            run("ansible-lint", "ansible-lint", "ansible")
        if Path("ansible/yamllint.conf").is_file():
            run("yamllint", "yamllint", "-c", "ansible/yamllint.conf", "ansible")
        else:
            run("yamllint", "yamllint", "ansible")
        if Path("ansible/main.yml").is_file():
            run(
                "ansible-syntax",
                "ansible-playbook",
                "--syntax-check",
                "ansible/main.yml",
            )
    else:
        record("skip", "ansible", "no ansible/ directory")

    if Path(".github/workflows").is_dir():
        run("zizmor", "zizmor", ".github/workflows")
        run("actionlint", "actionlint")
    else:
        record("skip", "actions", "no .github/workflows directory")

    dockerfiles = []
    for path in iter_repo_files():
        name = os.path.basename(path).lower()
        if name == "dockerfile" or name.startswith("dockerfile."):
            dockerfiles.append(path)

    if dockerfiles:
        if have("hadolint"):
            code = run_cmd(["hadolint", *dockerfiles])
            if code == 0:
                record("pass", "hadolint", f"{len(dockerfiles)} Dockerfile(s)")
            else:
                record(
                    "fail",
                    "hadolint",
                    f"exit {code}: {len(dockerfiles)} Dockerfile(s)",
                )
        else:
            record("skip", "hadolint", "missing hadolint")
    else:
        record("skip", "hadolint", "no Dockerfiles")

    if have("gitleaks"):
        run("gitleaks", "gitleaks", "detect", "--no-git", "--source", ".", "--redact")
    else:
        record("skip", "gitleaks", "missing gitleaks")

    if os.environ.get("REVIEW_GATE_FULL", "0") == "1":
        has_dotnet = any(
            path.endswith(".sln") or path.endswith(".csproj")
            for path in iter_repo_files()
        )
        if has_dotnet:
            run("dotnet-build", "dotnet", "build", "--nologo")
            run("dotnet-test", "dotnet", "test", "--nologo")
        else:
            record("skip", "dotnet", "no .sln or .csproj")

        if Path("Cargo.toml").is_file():
            run("cargo-fmt", "cargo", "fmt", "--check")
            run("cargo-clippy", "cargo", "clippy", "--all-targets", "--", "-D", "warnings")
            run("cargo-test", "cargo", "test")
        else:
            record("skip", "rust", "no Cargo.toml")
    else:
        record("skip", "dotnet", "REVIEW_GATE_FULL not set")
        record("skip", "rust", "REVIEW_GATE_FULL not set")

    summary = (
        f"\nSummary: {counts['pass']} pass, {counts['fail']} fail, "
        f"{counts['skip']} skip"
    )
    print(summary)
    log.write(summary + "\n")
    log.flush()
    print(f"Log: {log_path}")
    log.close()
    return 1 if counts["fail"] > 0 else 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Collect review context or run the deterministic review gate."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    context_parser = subparsers.add_parser("context", help="Collect review context.")
    context_parser.add_argument(
        "range", nargs="?", help="Git revision or range; defaults to origin/main..worktree."
    )

    gate_parser = subparsers.add_parser("gate", help="Run the deterministic review gate.")
    gate_parser.add_argument(
        "range", nargs="?", help="Git revision or range; defaults to origin/main..worktree."
    )

    args = parser.parse_args(argv)
    if shutil.which(GIT) is None:
        die("git is required")
    repo = repo_root()
    if args.command == "context":
        return run_context(repo, args.range)
    return run_gate(repo, args.range)


if __name__ == "__main__":
    sys.exit(main())
