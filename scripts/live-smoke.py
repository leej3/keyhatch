#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Opt-in read-only pilot check; invoke INSIDE keyhatch run, never print secrets.

Requires KEYHATCH_TEST_PASSWORD and WEBSITE_USERNAME from the CLI. Arguments:
absolute CLI path, approved hostname. No Passwords integration or installation.
"""
import base64
import json
import os
import resource
import shlex
import subprocess
import sys
import urllib.request

resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
try:
    cli, host = sys.argv[1:]
    secret = os.environ.pop("KEYHATCH_TEST_PASSWORD")
    account = os.environ.pop("WEBSITE_USERNAME")
    assert secret and account and host and "/" not in host and "@" not in host
    print("PASS: run supplied credential to the intended child (value withheld)")
    for _ in range(3):
        checked = subprocess.run([cli, "check", host, account], capture_output=True, timeout=10)
        assert checked.returncode == 0 and checked.stdout.strip() == b"available"
    print("PASS: repeated availability checks without new approval")
    helper = "!" + shlex.join([cli, "git", "--host", host, "--username", account])
    filled = subprocess.run(["git", "-c", "credential.helper=", "-c", f"credential.helper={helper}",
                             "credential", "fill"], input=f"protocol=https\nhost={host}\nusername={account}\n\n".encode(),
                            capture_output=True, timeout=10, env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
    assert filled.returncode == 0
    fields = dict(line.split(b"=", 1) for line in filled.stdout.splitlines() if b"=" in line)
    assert fields[b"password"].decode() == secret and fields[b"username"].decode() == account
    print("PASS: Git credential fill matches run delivery (values withheld)")
    denied = subprocess.run([cli, "check", "not-approved.invalid", account], capture_output=True, timeout=10)
    assert denied.returncode != 0
    mismatch = subprocess.run([cli, "git", "--host", host, "--username", account, "get"],
                              input=b"protocol=https\nhost=not-approved.invalid\n\n", capture_output=True, timeout=10)
    assert mismatch.returncode == 0 and not mismatch.stdout
    print("PASS: cross-host CLI and Git requests denied")

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    request = urllib.request.Request("https://" + host + "/api/v1/user")
    request.add_header("Authorization", "Basic " + base64.b64encode((account + ":" + secret).encode()).decode())
    request.add_header("Accept", "application/json")
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=20) as response:
        body = response.read(65537)
        assert response.status == 200 and len(body) <= 65536 and json.loads(body)["login"] == account
    print("PASS: read-only HTTPS identity check returned 200 and matching account")
except Exception:
    print("FAIL: live pilot check; diagnostic bodies withheld", file=sys.stderr)
    sys.exit(1)
