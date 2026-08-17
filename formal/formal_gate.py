#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, Optional, Tuple


DEFAULT_AXLE_BASE_URL = "https://axle.axiommath.ai/api/v1"
DEFAULT_LEAN_ENVIRONMENT = "lean-4.28.0"


@dataclass(frozen=True)
class AxleConfig:
    base_url: str
    api_key: str
    environment: str
    timeout_seconds: int


def _die(msg: str, *, code: int = 2) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def _find_aristotle_bin() -> str:
    # Prefer explicit override.
    override = os.environ.get("ARISTOTLE_BIN", "").strip()
    if override:
        return override

    found = shutil.which("aristotle")
    if found:
        return found

    # Common macOS user-site locations (as seen when installing aristotlelib with python3.11 --user).
    candidates = [
        Path.home() / "Library" / "Python" / "3.11" / "bin" / "aristotle",
        Path.home() / ".local" / "bin" / "aristotle",
    ]
    for c in candidates:
        if c.is_file():
            return str(c)

    _die(
        "Missing `aristotle` CLI. Install it with `python3 -m pip install --upgrade aristotlelib`, "
        "or set `ARISTOTLE_BIN` to the executable path.",
        code=2,
    )
    raise AssertionError("unreachable")


def _git_apply_check(repo_dir: Path, patch_path: Path, *, reverse: bool) -> subprocess.CompletedProcess[str]:
    cmd = ["git", "-C", str(repo_dir), "apply", "--check"]
    if reverse:
        cmd.append("--reverse")
    cmd.append(str(patch_path.resolve()))
    return subprocess.run(cmd, text=True, capture_output=True)


def _read_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        _die(f"Missing file: {path}", code=2)
    except json.JSONDecodeError as e:
        _die(f"Invalid JSON in {path}: {e}", code=2)

def _load_dotenv_if_present(dotenv_path: Path) -> None:
    if not dotenv_path.is_file():
        return
    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        # Respect already-set env vars.
        if os.environ.get(key):
            continue
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        os.environ[key] = value


def _read_text(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    return Path(path).read_text(encoding="utf-8")


def _axle_post_json(cfg: AxleConfig, endpoint: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    url = cfg.base_url.rstrip("/") + "/" + endpoint.lstrip("/")
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url=url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    # AXLE docs show unauthenticated examples, but we support API keys for paid/quota plans.
    req.add_header("Authorization", f"Bearer {cfg.api_key}")
    try:
        with urllib.request.urlopen(req, timeout=cfg.timeout_seconds) as resp:
            data = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        _die(f"AXLE HTTP {e.code} for {url}: {detail}", code=1)
    except urllib.error.URLError as e:
        _die(f"AXLE request failed for {url}: {e}", code=1)
    try:
        return json.loads(data)
    except json.JSONDecodeError:
        _die(f"AXLE returned non-JSON for {url}: {data[:500]}", code=1)


def axle_check(cfg: AxleConfig, *, content: str) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "content": content,
        "environment": cfg.environment,
        "timeout_seconds": cfg.timeout_seconds,
    }
    return _axle_post_json(cfg, "/check", payload)


def axle_verify_proof(cfg: AxleConfig, *, formal_statement: str, content: str) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "formal_statement": formal_statement,
        "content": content,
        "environment": cfg.environment,
        "timeout_seconds": cfg.timeout_seconds,
    }
    return _axle_post_json(cfg, "/verify_proof", payload)


def _find_statement_proof_pairs(directory: Path) -> Iterable[Tuple[Path, Path]]:
    statements = {p.stem.replace(".statement", ""): p for p in directory.glob("*.statement.lean")}
    proofs = {p.stem.replace(".proof", ""): p for p in directory.glob("*.proof.lean")}
    for stem, st_path in sorted(statements.items()):
        pr_path = proofs.get(stem)
        if pr_path is None:
            continue
        yield st_path, pr_path


def _require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        _die(f"Missing required env var `{name}`.", code=2)
    return value


def _axle_config_from_env(args: argparse.Namespace) -> AxleConfig:
    base_url = os.environ.get("AXLE_BASE_URL", DEFAULT_AXLE_BASE_URL).strip() or DEFAULT_AXLE_BASE_URL
    api_key = args.api_key or _require_env("AXLE_API_KEY")
    environment = args.environment or DEFAULT_LEAN_ENVIRONMENT
    timeout_seconds = int(args.timeout_seconds)
    return AxleConfig(base_url=base_url, api_key=api_key, environment=environment, timeout_seconds=timeout_seconds)


def _print_json(obj: Dict[str, Any]) -> None:
    print(json.dumps(obj, indent=2, sort_keys=True))


def cmd_axle_check(args: argparse.Namespace) -> None:
    cfg = _axle_config_from_env(args)
    content = _read_text(args.file)
    result = axle_check(cfg, content=content)
    _print_json(result)
    if not result.get("okay", False):
        raise SystemExit(3)


def cmd_axle_verify(args: argparse.Namespace) -> None:
    cfg = _axle_config_from_env(args)
    formal_statement = _read_text(args.statement)
    proof = _read_text(args.proof)
    result = axle_verify_proof(cfg, formal_statement=formal_statement, content=proof)
    _print_json(result)
    if not result.get("okay", False):
        raise SystemExit(3)


def cmd_verify_dir(args: argparse.Namespace) -> None:
    cfg = _axle_config_from_env(args)
    directory = Path(args.dir)
    if not directory.is_dir():
        _die(f"`--dir` must be a directory: {directory}", code=2)

    pairs = list(_find_statement_proof_pairs(directory))
    if not pairs:
        _die(f"No `*.statement.lean`/`*.proof.lean` pairs found in {directory}", code=2)

    any_failed = False
    for st_path, pr_path in pairs:
        formal_statement = st_path.read_text(encoding="utf-8")
        proof = pr_path.read_text(encoding="utf-8")
        result = axle_verify_proof(cfg, formal_statement=formal_statement, content=proof)
        ok = bool(result.get("okay", False))
        print(f"{st_path.name} + {pr_path.name}: {'OK' if ok else 'FAIL'}")
        if not ok:
            any_failed = True
    if any_failed:
        raise SystemExit(3)


def cmd_aristotle_submit(args: argparse.Namespace) -> None:
    api_key = args.api_key or _require_env("ARISTOTLE_API_KEY")
    project_dir = Path(args.project_dir)
    if not project_dir.is_dir():
        _die(f"`--project-dir` must be a directory: {project_dir}", code=2)

    aristotle_bin = _find_aristotle_bin()
    cmd = [
        aristotle_bin,
        "submit",
        args.prompt,
        "--project-dir",
        str(project_dir),
    ]
    if args.wait:
        cmd.append("--wait")

    env = dict(os.environ)
    env["ARISTOTLE_API_KEY"] = api_key
    raise SystemExit(subprocess.call(cmd, env=env))


def cmd_verify_manifest(args: argparse.Namespace) -> None:
    cfg = _axle_config_from_env(args)
    manifest_path = Path(args.manifest)
    manifest = _read_json(manifest_path)

    repo_info = manifest.get("repo", {})
    repo_dir = Path(str(repo_info.get("path", "")))
    if not repo_dir.is_dir():
        _die(f"Manifest repo path is not a directory: {repo_dir}", code=2)

    patch_path = Path(str(manifest.get("patch", "")))
    if not patch_path.is_file():
        _die(f"Manifest patch path is not a file: {patch_path}", code=2)

    # Patch sanity: ensure the patch either applies cleanly to the repo OR is already applied
    # (so it could be reversed). This avoids requiring a clean checkout in the artifact repo.
    apply_chk = _git_apply_check(repo_dir, patch_path, reverse=False)
    if apply_chk.returncode != 0:
        rev_chk = _git_apply_check(repo_dir, patch_path, reverse=True)
        if rev_chk.returncode != 0:
            _die(
                "Patch does not apply (or reverse-apply) cleanly to the target repo.\n"
                f"repo={repo_dir}\npatch={patch_path}\n\n"
                f"git apply --check stderr:\n{apply_chk.stderr}\n\n"
                f"git apply --reverse --check stderr:\n{rev_chk.stderr}",
                code=3,
            )

    contracts = manifest.get("contracts", [])
    if not isinstance(contracts, list) or not contracts:
        _die(f"Manifest has no contracts: {manifest_path}", code=2)

    any_failed = False
    for c in contracts:
        st_path = Path(str(c.get("statement", "")))
        pr_path = Path(str(c.get("proof", "")))
        if not st_path.is_file():
            _die(f"Missing statement file: {st_path}", code=2)
        if not pr_path.is_file():
            _die(f"Missing proof file: {pr_path}", code=2)

        formal_statement = st_path.read_text(encoding="utf-8")
        proof = pr_path.read_text(encoding="utf-8")
        result = axle_verify_proof(cfg, formal_statement=formal_statement, content=proof)
        ok = bool(result.get("okay", False))
        print(f"{manifest.get('id', manifest_path.name)}:{c.get('id', st_path.stem)}: {'OK' if ok else 'FAIL'}")
        if not ok:
            any_failed = True

    if any_failed:
        raise SystemExit(3)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="formal_gate.py", description="Formal diff-check gate (Lean).")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_axle_common(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("--api-key", default=None, help="AXLE API key (or set AXLE_API_KEY).")
        sp.add_argument("--environment", default=None, help=f"Lean environment (default: {DEFAULT_LEAN_ENVIRONMENT}).")
        sp.add_argument("--timeout-seconds", default="120", help="HTTP timeout seconds (default: 120).")

    sp = sub.add_parser("axle-check", help="Check Lean code via AXLE /check.")
    add_axle_common(sp)
    sp.add_argument("--file", required=True, help="Lean file path, or '-' for stdin.")
    sp.set_defaults(func=cmd_axle_check)

    sp = sub.add_parser("axle-verify", help="Verify proof vs statement via AXLE /verify_proof.")
    add_axle_common(sp)
    sp.add_argument("--statement", required=True, help="Lean statement file containing `sorry` placeholders.")
    sp.add_argument("--proof", required=True, help="Lean proof file intended to discharge the statement.")
    sp.set_defaults(func=cmd_axle_verify)

    sp = sub.add_parser("verify-dir", help="Verify all *.statement.lean/*.proof.lean pairs in a directory.")
    add_axle_common(sp)
    sp.add_argument("--dir", required=True, help="Directory containing proof/statement pairs.")
    sp.set_defaults(func=cmd_verify_dir)

    sp = sub.add_parser("aristotle-submit", help="Run Aristotle on a Lean project directory (sorry filling / repair).")
    sp.add_argument("--api-key", default=None, help="Aristotle API key (or set ARISTOTLE_API_KEY).")
    sp.add_argument("--project-dir", required=True, help="Lean project directory to submit.")
    sp.add_argument("--prompt", required=True, help="Natural language instruction for Aristotle.")
    sp.add_argument("--wait", action="store_true", help="Wait for the job to complete.")
    sp.set_defaults(func=cmd_aristotle_submit)

    sp = sub.add_parser("verify-manifest", help="Verify a diff+proof manifest: patch sanity + AXLE proof checks.")
    add_axle_common(sp)
    sp.add_argument("--manifest", required=True, help="Path to a JSON manifest file.")
    sp.set_defaults(func=cmd_verify_manifest)

    return p


def main(argv: Optional[Iterable[str]] = None) -> None:
    args = build_parser().parse_args(list(argv) if argv is not None else None)
    _load_dotenv_if_present(Path.cwd() / ".env")
    args.func(args)


if __name__ == "__main__":
    main()
