"""Writes tests/fixtures/state.json: a fresh Evolved war state from a real Obsidian Commander server,
for the offline tests and the previews.

Usage: python -P tools/fixture_state.py <commander-server.exe>

Starts the server on a free port with a scratch data folder, creates an Evolved war, starts a defense
on a Super Earth planet so both campaign kinds show, reads GET /w/<id>/evolved/state, and stops it.
"""
import json
import secrets
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent


def call(port, token, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=data, method=method,
                                 headers={"X-Commander-Token": token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    exe = sys.argv[1]
    data = Path(tempfile.mkdtemp(prefix="ewe-fixture-"))
    token = secrets.token_hex(8)
    proc = subprocess.Popen([exe, "--data", str(data), "--port", "0", "--token", token, "--ui", str(data)],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        line = proc.stdout.readline()
        port = int(line.split("port=")[1].split()[0])
        war = call(port, token, "POST", "/api/wars", {"name": "Second Galactic War", "model": "evolved"})
        wid = war["id"]
        # A defense too: a Super Earth planet linked to the cyborgs.
        state = call(port, token, "GET", f"/w/{wid}/evolved/state")
        galaxy = json.loads((HERE.parent.parent / "ProjectObsidian" / "ObsidianCommander" / "data" / "galaxy-hd2.json").read_text(encoding="utf-8"))
        owners = state["owners"]
        links = galaxy["links"]
        target = next(a if owners[a] == 0 else b for a, b in links
                      if {owners[a], owners[b]} == {0, 2} and (a if owners[a] == 0 else b) != 0)
        call(port, token, "POST", f"/api/wars/{wid}/actions", {"action": "evo_campaign", "planet": target, "kind": "defense", "faction": 2, "hours": 20})
        call(port, token, "POST", f"/api/wars/{wid}/actions", {"action": "evo_news", "text": "Cyborg forces push across the western supply lines. High Command calls every Helldiver to the front."})
        state = call(port, token, "GET", f"/w/{wid}/evolved/state")
        # Some progress, so the bars show.
        for c in state["campaigns"][:2]:
            op = c["operations"][0]
            req = urllib.request.Request(f"http://127.0.0.1:{port}/w/{wid}/evolved/report", method="POST",
                                         data=json.dumps({"campaign": c["id"], "operation": op["id"], "mission": 0, "success": True, "lobby": "fixture"}).encode(),
                                         headers={"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=10).read()
        state = call(port, token, "GET", f"/w/{wid}/evolved/state")
    finally:
        proc.stdin.close()
        proc.wait(timeout=10)
        shutil.rmtree(data, ignore_errors=True)
    dest = HERE / "tests" / "fixtures" / "state.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    with open(dest, "w", encoding="utf-8", newline="\n") as f:
        json.dump(state, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"{dest}: {len(state['campaigns'])} campaigns, {len(state['orders'])} orders, {len(state['news'])} news")


if __name__ == "__main__":
    main()
