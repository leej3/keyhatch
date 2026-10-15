#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Synthetic, separate-process mutual-authentication integration checks on macOS."""
import json
import os
from pathlib import Path
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parent.parent
subprocess.run(["swift", "build", "--scratch-path", ".build/keyhatch", "--product", "KeyhatchIPCFixture"], cwd=root, check=True)
binary_dir = subprocess.check_output(["swift", "build", "--scratch-path", ".build/keyhatch", "--show-bin-path"], cwd=root, text=True).strip()

def sign(path, identity):
    subprocess.run(["codesign", "--force", "--options", "runtime", "--sign", "-", "--identifier", identity, str(path)], check=True, capture_output=True)
    detail = subprocess.run(["codesign", "-d", "--verbose=4", str(path)], capture_output=True, text=True, check=True)
    return re.search(r"^CDHash=([0-9a-f]{40})$", detail.stderr, re.M)[1]

def wait_socket(path, proc):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if path.exists():
            return
        if proc.poll() is not None:
            raise AssertionError("fixture server exited")
        time.sleep(0.05)
    raise AssertionError("fixture server startup timed out")

with tempfile.TemporaryDirectory(prefix="kh-ipc-", dir="/tmp") as directory:
    base = Path(directory)
    paths = {name: base / name for name in ("server", "client", "wrong-client")}
    hashes = {}
    for name, path in paths.items():
        shutil.copy2(Path(binary_dir) / "KeyhatchIPCFixture", path)
        hashes[name] = sign(path, "local.keyhatch.test." + name)
    state = base / "state"
    state.mkdir(mode=0o700)
    endpoint = state / "broker.sock"
    server = subprocess.Popen([str(paths["server"]), "server", str(state), hashes["client"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_socket(endpoint, server)
        assert endpoint.stat().st_mode & 0o777 == 0o600
        def call(name, server_hash):
            return subprocess.run([str(paths[name]), "client", str(endpoint), server_hash], capture_output=True, text=True, timeout=8)
        assert call("client", hashes["server"]).returncode == 0
        print("PASS: kernel audit-token mutual code-identity authentication")
        assert call("wrong-client", hashes["server"]).returncode != 0
        assert call("client", "0" * 40).returncode != 0
        print("PASS: wrong client and wrong server code hashes denied")
        # An untrusted Python process is rejected before its frame is decoded.
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(3)
            connection.connect(str(endpoint))
            try:
                connection.sendall(struct.pack(">I", 0xffffffff))
                assert not connection.recv(16)
            except (ConnectionResetError, BrokenPipeError):
                pass
        assert call("client", hashes["server"]).returncode == 0
        print("PASS: untrusted malformed client denied; broker remains usable")
        duplicate = subprocess.run([str(paths["server"]), "server", str(state), hashes["client"]], capture_output=True, timeout=5)
        assert duplicate.returncode != 0
        print("PASS: duplicate broker cannot replace live socket")
    finally:
        server.terminate()
        server.wait(timeout=5)
    # Crash left a socket: next lock owner must recover it safely.
    server = subprocess.Popen([str(paths["server"]), "server", str(state), hashes["client"]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(40):
            if call("client", hashes["server"]).returncode == 0:
                break
            time.sleep(0.05)
        else:
            raise AssertionError("stale socket recovery failed")
        print("PASS: stale-socket recovery after process exit")
    finally:
        server.terminate()
        server.wait(timeout=5)
print("IPC integration passed; only synthetic data used.")
