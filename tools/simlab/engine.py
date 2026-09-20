"""JSONL transport to the single Luau rules authority."""
import json
import os
import queue
import shutil
import subprocess
import threading
from pathlib import Path


def lune_executable():
    candidate = Path.home() / ".rokit" / "bin" / ("lune.exe" if os.name == "nt" else "lune")
    found = str(candidate) if candidate.exists() else shutil.which("lune")
    if not found:
        raise RuntimeError("Lune unavailable; run tools/bootstrap.ps1")
    return found


class Engine:
    def __init__(self, source, bridge="tools/simlab/bridge.luau"):
        self.source = Path(source)
        self.process = subprocess.Popen(
            [lune_executable(), "run", str(self.source / bridge)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", bufsize=1, cwd=self.source,
        )
        self.lines = queue.Queue()
        self.errors = []
        def read_stdout():
            for line in self.process.stdout:
                self.lines.put(line)
            self.lines.put(None)
        def read_stderr():
            for line in self.process.stderr:
                self.errors.append(line)
        threading.Thread(target=read_stdout, daemon=True).start()
        threading.Thread(target=read_stderr, daemon=True).start()

    def call(self, op, **kwargs):
        self.process.stdin.write(json.dumps(dict(op=op, **kwargs), allow_nan=False) + "\n")
        self.process.stdin.flush()
        try:
            line = self.lines.get(timeout=30)
        except queue.Empty as exc:
            self.close()
            raise RuntimeError("Rules engine timed out") from exc
        if not line:
            raise RuntimeError("Rules engine exited: " + "".join(self.errors)[-2000:])
        response = json.loads(line)
        if not response["ok"]:
            raise ValueError(response["error"])
        return response["result"]

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        for stream in (self.process.stdout, self.process.stderr):
            stream.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()
