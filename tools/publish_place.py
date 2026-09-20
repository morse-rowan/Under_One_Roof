"""Publish the private presentation place to Roblox through Open Cloud.

Builds the release with `package_presentation`, so the compiled place is the one
whose configuration was verified, then uploads it as a new published version of
an existing place. It creates nothing: the experience must already exist, which
is a one-time step in Studio (File > Publish to Roblox As...) or on the Creator
Dashboard. After that every later update is one command.

    py -3 tools/publish_place.py --universe 123 --place 456 --offline
    py -3 tools/publish_place.py --offline                  # remembers the target
    py -3 tools/publish_place.py --offline --dry-run        # build and check only

The API key is read from ROBLOX_API_KEY. `tools/publish_place.ps1` decrypts the
stored key into that variable for you; the key is never written to the repo.
"""

import argparse
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parent))
import package_presentation  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
STORE = Path(os.environ.get("LOCALAPPDATA") or Path.home() / ".config") / "SteelhacksRoommate"
TARGET_FILE = STORE / "roblox-place.json"
PLACE_FILE = ROOT / "build" / "presentation" / "RoommatePresentation.rbxlx"
API = "https://apis.roblox.com/universes/v1/{universe}/places/{place}/versions"


def content_type(path):
    """Open Cloud distinguishes the XML and binary place formats by media type."""
    suffix = Path(path).suffix.lower()
    if suffix == ".rbxlx":
        return "application/xml"
    if suffix == ".rbxl":
        return "application/octet-stream"
    raise ValueError(f"Not a Roblox place file: {path}")


def version_url(universe, place):
    # `type(...) is not int` rather than isinstance: a bool is an int in Python and
    # would format as 1, silently addressing the wrong place. Same guard the
    # release builder uses on invited user IDs.
    if any(type(value) is not int or value <= 0 for value in (universe, place)):
        raise ValueError("Universe and place IDs must be positive integers")
    return API.format(universe=universe, place=place) + "?versionType=Published"


def load_target(universe=None, place=None, store=TARGET_FILE):
    """Explicit arguments win, then the environment, then the remembered target."""
    saved = {}
    if store.is_file():
        try:
            saved = json.loads(store.read_text(encoding="utf-8"))
        except ValueError:
            saved = {}

    def pick(given, variable, field):
        if given:
            return int(given)
        if os.environ.get(variable):
            return int(os.environ[variable])
        return int(saved.get(field) or 0) or None

    resolved_universe = pick(universe, "ROBLOX_UNIVERSE_ID", "universeId")
    resolved_place = pick(place, "ROBLOX_PLACE_ID", "placeId")
    if not resolved_universe or not resolved_place:
        raise ValueError(
            "No target yet. Pass --universe and --place once; they are remembered at "
            f"{store}. Both IDs are on the experience's Creator Dashboard page.")
    return resolved_universe, resolved_place


def save_target(universe, place, store=TARGET_FILE):
    store.parent.mkdir(parents=True, exist_ok=True)
    store.write_text(json.dumps({"universeId": universe, "placeId": place}, indent=2),
                     encoding="utf-8")


def describe_failure(status, body):
    """Open Cloud's own message, plus the cause these two statuses almost always have."""
    hint = {
        401: "The API key was rejected. Check it was pasted whole and has not expired.",
        403: "The key authenticated but is not allowed here. It needs the "
             "universe-places:write scope AND this universe listed in the key's "
             "access permissions.",
        404: "No such universe or place. Both IDs come from the Creator Dashboard; "
             "the place ID is not the universe ID.",
    }.get(status)
    return "\n".join(filter(None, [f"Roblox returned HTTP {status}.", body.strip() or None, hint]))


def publish(place_file, universe, place, key):
    data = Path(place_file).read_bytes()
    request = urllib.request.Request(
        version_url(universe, place),
        data=data,
        method="POST",
        headers={"x-api-key": key, "Content-Type": content_type(place_file)},
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            body = response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(describe_failure(exc.code, exc.read().decode("utf-8", "replace"))) from exc
    try:
        return json.loads(body).get("versionNumber")
    except ValueError:
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--offline", action="store_true",
                      help="deterministic roommates; needs no gateway and no secrets")
    mode.add_argument("--gateway-url", help="https://<host>/decide for live model roommates")
    parser.add_argument("--invite", type=int, action="append", default=[],
                        help="numeric Roblox user ID allowed to join; repeatable")
    parser.add_argument("--universe", type=int)
    parser.add_argument("--place", type=int)
    parser.add_argument("--place-file", help="publish this file instead of rebuilding")
    parser.add_argument("--dry-run", action="store_true",
                        help="build and validate, then stop without uploading")
    args = parser.parse_args()

    try:
        universe, place = load_target(args.universe, args.place)
        if args.place_file:
            place_file = Path(args.place_file)
            if not place_file.is_file():
                raise ValueError(f"No such place file: {place_file}")
        else:
            package_presentation.build(args.gateway_url, args.invite)
            place_file = PLACE_FILE
        size = place_file.stat().st_size
        print(f"Place:    {place_file} ({size / 1024:.0f} KiB)")
        print(f"Target:   universe {universe}, place {place}")
        print(f"Mode:     {'live gateway ' + args.gateway_url if args.gateway_url else 'offline, deterministic roommates'}")
        print(f"Invited:  {sorted(set(args.invite)) or 'nobody beyond the owner and Studio'}")
        if args.dry_run:
            print("Dry run: nothing was uploaded.")
            return 0
        key = os.environ.get("ROBLOX_API_KEY", "").strip()
        if not key:
            raise ValueError(
                "No ROBLOX_API_KEY. Run tools/save_roblox_key.ps1 once, then use "
                "tools/publish_place.ps1, which decrypts it into the environment.")
        version = publish(place_file, universe, place, key)
        save_target(universe, place)
        print(f"Published version {version}.")
        print(f"Play:     https://www.roblox.com/games/{place}")
        print("The experience's Audience setting still governs who may join.")
        return 0
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
