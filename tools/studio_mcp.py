"""Call one Roblox Studio MCP tool from the command line.

A thin, reusable wrapper around the same stdio JSON-RPC launcher that
`check_studio_mcp.py` uses for its read-only check. It spends no inference and
holds no credentials; whatever the named tool does is the whole effect.

    py -3 tools/studio_mcp.py get_studio_state
    py -3 tools/studio_mcp.py run --code "return game.PlaceId"
    py -3 tools/studio_mcp.py <tool> --json '{"key": "value"}'

`run` is shorthand for `execute_luau` against the single connected Studio, which
is the common case. With more than one Studio open, pass --studio explicitly.
"""

import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import time


class Studio:
    def __init__(self, timeout=30):
        launcher = Path(os.environ.get("LOCALAPPDATA", "")) / "Roblox" / "mcp.bat"
        if os.name != "nt" or not launcher.is_file():
            raise RuntimeError("Open current Windows Roblox Studio: mcp.bat was not found.")
        self.timeout = timeout
        self.process = subprocess.Popen(
            ["cmd.exe", "/d", "/c", str(launcher)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        self.messages = queue.Queue()
        self.request_id = 0
        threading.Thread(target=self._read, daemon=True).start()
        self.send("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "roommate-studio-mcp", "version": "1.0"},
        })
        self.send("notifications/initialized", {}, notification=True)

    def _read(self):
        try:
            for line in self.process.stdout:
                try:
                    self.messages.put(json.loads(line))
                except json.JSONDecodeError:
                    self.messages.put({"error": "Non-JSON output from the Studio MCP launcher"})
        finally:
            self.messages.put({"error": "Studio MCP launcher closed stdout"})

    def send(self, method, params, notification=False):
        self.request_id += 1
        message = {"jsonrpc": "2.0", "method": method, "params": params}
        if not notification:
            message["id"] = self.request_id
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()
        if notification:
            return None
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Studio MCP response timed out")
            try:
                response = self.messages.get(timeout=remaining)
            except queue.Empty as exc:
                raise TimeoutError("Studio MCP response timed out") from exc
            if "error" in response:
                raise RuntimeError(str(response["error"]))
            if response.get("id") == self.request_id:
                return response["result"]

    def studios(self):
        found = []
        for attempt in range(4):
            if attempt:
                time.sleep(1)
            result = self.call("list_roblox_studios", {}, raw=True)
            for item in result.get("content", []):
                if item.get("type") == "text":
                    found.extend(json.loads(item["text"]).get("studios", []))
            if found:
                break
        return found

    def call(self, name, arguments, raw=False):
        result = self.send("tools/call", {"name": name, "arguments": arguments})
        if result.get("isError"):
            raise RuntimeError(json.dumps(result.get("content"), ensure_ascii=False))
        if raw:
            return result
        parts = [item.get("text", "") for item in result.get("content", [])
                 if item.get("type") == "text"]
        return "\n".join(parts)

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill.exe", "/PID", str(self.process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           check=False, creationflags=subprocess.CREATE_NO_WINDOW)
            self.process.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("tool", help="MCP tool name, or 'run' for execute_luau")
    parser.add_argument("--json", default="{}", help="tool arguments as a JSON object")
    parser.add_argument("--code", help="Luau source, for 'run'")
    parser.add_argument("--studio", help="studio_id when several are connected")
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    studio = Studio(timeout=args.timeout)
    try:
        arguments = json.loads(args.json)
        if not isinstance(arguments, dict):
            raise ValueError("--json must be a JSON object")
        name = args.tool
        if name == "run":
            name = "execute_luau"
            if args.code is None:
                raise ValueError("run needs --code")
            arguments.setdefault("command", args.code)
        needs_studio = name not in {"list_roblox_studios"}
        if needs_studio and "studio_id" not in arguments:
            studio_id = args.studio
            if not studio_id:
                found = studio.studios()
                if len(found) != 1:
                    raise RuntimeError(
                        f"Expected exactly one connected Studio, found {len(found)}: "
                        + json.dumps(found, ensure_ascii=False))
                studio_id = found[0]["id"]
            arguments["studio_id"] = studio_id
        print(studio.call(name, arguments))
        return 0
    except (OSError, RuntimeError, TimeoutError, KeyError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    finally:
        studio.close()


if __name__ == "__main__":
    sys.exit(main())
