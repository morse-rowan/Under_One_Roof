"""Public command-line interface; JSON on stdout, actionable errors on stderr."""
import argparse
import json
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from . import analysis, campaigns, config, runner
from .engine import Engine
from .storage import atomic, journal, load_checkpoint, lock, read, verify_source


def parser():
    p = argparse.ArgumentParser(description="Roommate simulation research suite")
    p.add_argument("--root", default=os.environ.get("ROOMMATE_LAB_ROOT", str(config.ROOT / "simulation-data")), help="Durable artifact root, never build/")
    commands = p.add_subparsers(dest="command", required=True)
    for name in ("validate", "run", "batch"):
        cmd = commands.add_parser(name)
        cmd.add_argument("--scenario", default="bargaining")
        cmd.add_argument("--set", action="append", default=[], dest="overrides", metavar="PATH=JSON")
        cmd.add_argument("--live", action="store_true")
        if name != "validate":
            cmd.add_argument("--max-steps", type=int)
        if name == "batch":
            cmd.add_argument("--seeds", default="11,29,47")
            cmd.add_argument("--workers", type=int, default=1)
    for name in ("inspect", "replay", "resume", "branch", "evaluate", "stop", "export"):
        cmd = commands.add_parser(name)
        cmd.add_argument("path")
        if name in {"inspect", "branch"}:
            cmd.add_argument("--checkpoint", type=int)
        if name == "inspect":
            cmd.add_argument("--actor")
            cmd.add_argument("--tag")
        if name in {"resume", "branch", "evaluate"}:
            cmd.add_argument("--live", action="store_true")
        if name in {"resume", "branch"}:
            cmd.add_argument("--max-steps", type=int)
        if name == "resume":
            cmd.add_argument("--clear-stop", action="store_true")
            cmd.add_argument("--campaign-stop", help=argparse.SUPPRESS)
        if name == "branch":
            cmd.add_argument("--set", action="append", default=[], dest="overrides")
            cmd.add_argument("--choice", type=int)
            cmd.add_argument("--continue", action="store_true", dest="continue_run")
        if name == "evaluate":
            cmd.add_argument("--provider", choices=["offline", "nvidia", "codex", "claude"], default="offline")
        if name == "export":
            cmd.add_argument("--output", required=True)
    cmd = commands.add_parser("compare")
    cmd.add_argument("paths", nargs="+")
    cmd.add_argument("--output")
    cmd = commands.add_parser("search")
    cmd.add_argument("--config")
    cmd.add_argument("--resume")
    cmd.add_argument("--live", action="store_true")
    cmd.add_argument("--holdout", action="store_true")
    cmd.add_argument("--clear-stop", action="store_true")
    cmd = commands.add_parser("experiment")
    cmd.add_argument("proposal")
    cmd.add_argument("--agent", choices=["codex", "claude"], default="codex")
    cmd.add_argument("--live", action="store_true")
    commands.add_parser("index")
    return p


def execute(args):
    root = Path(args.root).resolve()
    if root == (config.ROOT / "build").resolve() or (config.ROOT / "build").resolve() in root.parents:
        raise ValueError("Experiment artifacts cannot use disposable build/")
    cmd = args.command
    if cmd in {"validate", "run", "batch"}:
        cfg = config.load(args.scenario, args.overrides)
        if cmd == "validate":
            result = {"valid": True, "config": cfg}
            if args.live:
                from . import policies
                import uuid
                result["provider"] = policies.preflight(cfg["inference"], root, root / "launch-checks" / f"{uuid.uuid4().hex}.json")
                result["provider"].pop("raw_response", None)
            return result
        if cmd == "run":
            path = runner.new_run(root, cfg)
            return runner.drive(path, root, args.live, args.max_steps)
        from concurrent.futures import ThreadPoolExecutor
        if not 1 <= args.workers <= 16:
            raise ValueError("workers must be 1..16")
        paths = []
        for seed in map(int, args.seeds.split(",")):
            variant = config.load(args.scenario, args.overrides + [f"seed={seed}"])
            paths.append(runner.new_run(root, variant))
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            results = list(pool.map(lambda path: runner.drive(path, root, args.live, args.max_steps), paths))
        return {"runs": results, "comparison": analysis.compare(paths)}
    if cmd == "index":
        return {"runs": [{"path": str(p), "status": read(p / "status.json") if (p / "status.json").exists() else {"status": "interrupted"}, "tags": read(p / "tags.json")} for p in sorted((root / "runs").glob("*")) if (p / "manifest.json").exists()],
                "campaigns": [str(p) for p in sorted((root / "campaigns").glob("*"))]}
    if cmd == "compare":
        result = analysis.compare(args.paths)
        if args.output:
            atomic(args.output, result)
        return result
    if cmd == "search":
        if args.resume and args.clear_stop:
            (Path(args.resume) / "STOP").unlink(missing_ok=True)
        return campaigns.search(root, read(args.config) if args.config else None, args.resume, args.live, args.holdout)
    if cmd == "experiment":
        return campaigns.experiment(root, read(args.proposal), args.agent, args.live)
    path = Path(args.path).resolve()
    if cmd == "replay":
        return runner.replay(path)
    if cmd == "resume":
        if args.clear_stop:
            (path / "STOP").unlink(missing_ok=True)
        return runner.drive(path, root, args.live, args.max_steps, stop_file=args.campaign_stop)
    if cmd == "branch":
        child = runner.branch(path, root, args.checkpoint, args.overrides, args.choice)
        return runner.drive(child, root, args.live, args.max_steps) if args.continue_run else {"run": str(child), "status": "ready"}
    if cmd == "inspect":
        number, payload = load_checkpoint(path, args.checkpoint)
        if args.tag:
            with lock(path):
                tags = read(path / "tags.json")
                tags.append({"checkpoint": number, "tag": args.tag})
                atomic(path / "tags.json", tags)
        if args.actor:
            with Engine(verify_source(path)) as engine:
                return engine.call("observe", state=payload["state"], config=runner.verify_config(path), actor=args.actor)
        return {"checkpoint": number, "payload": payload, "metrics": analysis.summarize(path), "perspective": "omniscient audit"}
    if cmd == "evaluate":
        return analysis.evaluate(path, root, args.provider, args.live)
    if cmd == "stop":
        if not (path / "config.json").exists():
            raise ValueError("Not a run or campaign")
        atomic(path / "STOP", {"reason": "user_requested"})
        return {"stop_requested": str(path), "effect": "checkpoint boundary after any in-flight request"}
    if cmd == "export":
        destination = Path(args.output).resolve()
        if path == destination or path in destination.parents:
            raise ValueError("Export destination must be outside the run")
        runner.replay(path)
        with lock(path):
            destination.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
                for file in sorted(path.rglob("*")):
                    if file.is_file() and file.name != ".writer.lock" and "__pycache__" not in file.parts:
                        archive.write(file, file.relative_to(path))
        return {"export": str(destination), "bytes": destination.stat().st_size}
    raise ValueError("Unsupported command")


def main():
    args = parser().parse_args()
    try:
        result = execute(args)
        print(json.dumps(result, indent=2, ensure_ascii=True, allow_nan=False))
    except KeyboardInterrupt:
        print(json.dumps({"error": "interrupted", "recovery": "Resume from the last committed checkpoint."}), file=sys.stderr)
        return 130
    except (ValueError, RuntimeError, OSError, KeyError, IndexError, TypeError) as exc:
        print(json.dumps({"error": str(exc), "type": type(exc).__name__}), file=sys.stderr)
        return 1
    return 0
