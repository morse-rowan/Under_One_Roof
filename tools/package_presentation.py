"""Build a private presentation bundle without modifying source or uploading it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def build(gateway_url=None, invited=()):
    if gateway_url:
        parsed = urllib.parse.urlsplit(gateway_url)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.username
                or parsed.password or parsed.query or parsed.fragment
                or parsed.path != "/decide"):
            raise ValueError("Use an HTTPS gateway URL ending in /decide, with no credentials or query")
    if any(type(uid) is not int or uid <= 0 for uid in invited):
        raise ValueError("Invited Roblox user IDs must be positive integers")
    out = ROOT / "build" / "presentation"
    if out.exists():
        # Stale artifacts from an earlier run are a demo hazard, not a cache.
        shutil.rmtree(out)
    out.mkdir(parents=True)
    live = gateway_url is not None
    # Override inside a staged copy of the tree rather than beside it. Writing a
    # sibling child next to the `$path` directory that already supplies the file
    # left two modules with the same name under one parent, and `require` picks
    # either one, so a release could silently load the default configuration.
    staged = out / "src"
    shutil.copytree(ROOT / "src", staged)
    info = (ROOT / "src/shared/BuildInfo.luau").read_text(encoding="utf-8")
    # State the brain switch outright in both configurations. Reading it as
    # "whatever the working tree happens to default to" made an offline release
    # ship live the moment that default flipped.
    on, off = info.count("enabled = true"), info.count("enabled = false")
    if on + off != 1:
        raise ValueError("BuildInfo switch changed; inspect the release builder before use")
    info = info.replace(
        "enabled = true" if on else "enabled = false",
        "enabled = true" if live else "enabled = false", 1)
    (staged / "shared" / "BuildInfo.luau").write_text(info, encoding="utf-8")
    config = "return {\n    allowedUserIds = {%s},\n    brainUrl = %s,\n    brainSecretName = \"ROOMMATE_GATEWAY_TOKEN\",\n}\n" % (
        ", ".join(map(str, sorted(set(invited)))),
        json.dumps(gateway_url or "http://127.0.0.1:8787/decide"),
    )
    (staged / "server" / "PresentationConfig.luau").write_text(config, encoding="utf-8")
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))

    source_root = (ROOT / "src").resolve()

    def absolute_paths(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "$path":
                    original = (ROOT / value).resolve()
                    # Anything under src/ is served from the staged copy, so the
                    # overrides above are the only BuildInfo and PresentationConfig
                    # the compiled place can contain.
                    if original == source_root or source_root in original.parents:
                        node[key] = str(staged / original.relative_to(source_root))
                    else:
                        node[key] = str(original)
                else:
                    absolute_paths(value)
    absolute_paths(project)
    tree = project["tree"]
    tree["HttpService"] = {"$className": "HttpService", "$properties": {"HttpEnabled": live}}
    project_file = out / "release.project.json"
    project_file.write_text(json.dumps(project, indent=2), encoding="utf-8")
    pinned = Path(os.environ.get("USERPROFILE", "")) / ".rokit/bin/rojo.exe"
    rojo = str(pinned) if pinned.is_file() else shutil.which("rojo")
    if not rojo:
        raise RuntimeError("Install the pinned tools with tools/bootstrap.ps1 first")
    place = out / "RoommatePresentation.rbxlx"
    subprocess.run([rojo, "build", str(project_file), "--output", str(place)], check=True, cwd=ROOT)
    # Verify the compiled artifact, not merely the staging configuration.
    document = ET.parse(place)
    sources = {}
    for item in document.iter("Item"):
        props = item.find("Properties")
        if props is None:
            continue
        name = props.find("string[@name='Name']")
        # Rojo writes Source as a plain string element; older places use
        # ProtectedString. Accept both, because matching neither silently
        # passed every place through this check.
        source = props.find("string[@name='Source']")
        if source is None:
            source = props.find("ProtectedString[@name='Source']")
        if name is not None and source is not None:
            sources.setdefault(name.text, []).append(source.text or "")
    for module, expected in (("PresentationConfig", config), ("BuildInfo", info)):
        found = sources.get(module, [])
        if len(found) != 1:
            raise RuntimeError(
                "Expected exactly one %s in the compiled place, found %d" % (module, len(found)))
        if found[0] != expected:
            raise RuntimeError("Compiled place does not match the requested private release configuration")
    gateway = out / "gateway"
    gateway.mkdir(exist_ok=True)
    shutil.copyfile(ROOT / "tools/nemotron_proxy.py", gateway / "nemotron_proxy.py")
    (gateway / "Dockerfile").write_text(
        'FROM python:3.12-slim\nWORKDIR /app\nCOPY nemotron_proxy.py .\n'
        'USER 65532:65532\nEXPOSE 8080\n'
        'CMD ["python", "nemotron_proxy.py", "--host", "0.0.0.0", "--port", "8080", "--max-calls", "120"]\n',
        encoding="utf-8")
    (gateway / ".env.example").write_text("NVIDIA_API_KEY=\nROOMMATE_GATEWAY_TOKEN=\n", encoding="utf-8")
    files = [place, gateway / "nemotron_proxy.py", gateway / "Dockerfile", gateway / ".env.example"]
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    manifest = {
        "sourceCommit": revision,
        "sourceHasChanges": bool(subprocess.check_output(["git", "diff", "HEAD", "--name-only"], cwd=ROOT, text=True).strip()),
        "live": live, "gatewayUrl": gateway_url, "invitedUserIds": sorted(set(invited)),
        "published": False,
        "requiredConfiguration": ["Private Roblox access and invited playtesters", "Max players: 1",
            "HTTPS host with its HTTP port private", "Backend environment secrets",
            "Roblox ROOMMATE_GATEWAY_TOKEN secret scoped to the gateway host"] if live else [],
        "sha256": {str(f.relative_to(out)).replace('\\', '/'): hashlib.sha256(f.read_bytes()).hexdigest() for f in files},
    }
    manifest_file = out / "manifest.json"
    manifest_file.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    archive = out / "roommate-presentation.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
        for file in files + [manifest_file]:
            bundle.write(file, file.relative_to(out))
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--offline", action="store_true")
    mode.add_argument("--gateway-url")
    parser.add_argument("--invite", type=int, action="append", default=[])
    args = parser.parse_args()
    print(build(args.gateway_url, args.invite))
