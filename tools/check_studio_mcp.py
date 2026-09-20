"""Read-only connection check for Roblox's built-in Windows Studio MCP server.

Uses Python's standard library; no inference, credentials, or game writes.
Exit 0: tools and a Studio instance found. Exit 1: connection/protocol failure.
Exit 2: proxy responds, but Studio's MCP toggle/place is not ready.
"""

import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import time


def main():
    launcher = Path(os.environ.get("LOCALAPPDATA", "")) / "Roblox" / "mcp.bat"
    if os.name != "nt" or not launcher.is_file():
        print("Install/open current Windows Roblox Studio: mcp.bat was not found.")
        return 1

    process = subprocess.Popen(
        ["cmd.exe", "/d", "/c", str(launcher)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
    messages = queue.Queue()

    def read_output():
        try:
            for line in process.stdout:
                try:
                    messages.put(json.loads(line))
                except json.JSONDecodeError:
                    messages.put({"error": "Non-JSON output from Studio MCP launcher"})
        finally:
            messages.put({"error": "Studio MCP launcher closed stdout"})

    threading.Thread(target=read_output, daemon=True).start()
    request_id = 0

    def send(method, params, notification=False):
        nonlocal request_id
        request_id += 1
        message = {"jsonrpc": "2.0", "method": method, "params": params}
        if not notification:
            message["id"] = request_id
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()
        if notification:
            return None
        deadline = time.monotonic() + 20
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Studio MCP response timed out")
            try:
                response = messages.get(timeout=remaining)
            except queue.Empty as exc:
                raise TimeoutError("Studio MCP response timed out") from exc
            if "error" in response:
                raise RuntimeError(str(response["error"]))
            if response.get("id") == request_id:
                return response["result"]

    try:
        initialized = send("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "roommate-mcp-check", "version": "1.0"},
        })
        send("notifications/initialized", {}, notification=True)
        print("MCP server:", initialized["serverInfo"]["name"])
        tools = send("tools/list", {}).get("tools", [])
        names = sorted(tool["name"] for tool in tools)
        print(f"Available tools ({len(names)}):", ", ".join(names) or "none")
        # This discovery method responds even while the proxy advertises zero tools.
        studios = []
        # The proxy can briefly advertise tools before instance registration arrives.
        for attempt in range(4):
            if attempt:
                time.sleep(1)
            result = send("tools/call", {
                "name": "list_roblox_studios", "arguments": {},
            })
            if result.get("isError"):
                raise RuntimeError(str(result.get("content")))
            for item in result.get("content", []):
                if item.get("type") == "text":
                    data = json.loads(item["text"])
                    studios.extend(data.get("studios", []))
            if studios:
                break
        print("Connected Studio instances:", json.dumps(studios, ensure_ascii=False))
        if not names or not studios:
            print("Open the development place, then Assistant > ... > Manage MCP "
                  "Servers > Enable Studio as MCP server. Rerun this check.")
            return 2
        if len(studios) == 1 and "get_studio_state" in names:
            state = send("tools/call", {
                "name": "get_studio_state",
                "arguments": {"studio_id": studios[0]["id"]},
            })
            if state.get("isError"):
                raise RuntimeError(str(state.get("content")))
            print("Live Studio state:", json.dumps(state.get("content", [])))
        print("PASS: Studio connection and tool discovery work. "
              "No scripts changed and no playtest started.")
        return 0
    except (OSError, RuntimeError, TimeoutError, KeyError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    finally:
        # EOF lets the proxy and its cmd parent shut down normally.
        process.stdin.close()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            subprocess.run(
                ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
                creationflags=subprocess.CREATE_NO_WINDOW,
            )
            process.wait(timeout=3)


if __name__ == "__main__":
    sys.exit(main())
