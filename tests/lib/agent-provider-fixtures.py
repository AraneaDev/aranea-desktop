#!/usr/bin/env python3
"""Capture target collectors with disposable credentials and inert transport only."""
import base64
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse

root = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
# Nothing inherited may name a real credential, home or provider endpoint.
private = out.parent / "provider-home"
private.mkdir()
os.environ.clear()
os.environ.update(HOME=str(private), OMARCHY_PATH=str(root),
                  PATH=str(private / "bin"), PYTHONDONTWRITEBYTECODE="1")
for kind, suffix in (("CONFIG", ".config"), ("STATE", ".local/state"),
                     ("DATA", ".local/share"), ("CACHE", ".cache")):
    directory = private / suffix
    directory.mkdir(parents=True, exist_ok=True)
    os.environ[f"XDG_{kind}_HOME"] = str(directory)
sys.dont_write_bytecode = True


def no_network(event, _args):
    """Fail closed if a collector ever escapes its transport fixture."""
    if event in ("socket.connect", "socket.getaddrinfo"):
        raise RuntimeError("provider fixture forbids network")


sys.addaudithook(no_network)


def write(path, value):
    """Write a private input or captured JSON record."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))


def load(provider):
    """Load the complete target collector, without extracting its functions."""
    loader = importlib.machinery.SourceFileLoader(provider, str(root / "bin" / f"omarchy-agent-usage-{provider}"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def collect(provider):
    """Run the actual collector main and capture its emitted protocol record."""
    module = load(provider)
    if provider == "fireworks":
        module.open_json = billing_response
    sys.argv = [provider, "--force"]
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        result = module.main()
    if result not in (None, 0):
        raise RuntimeError(f"{provider} failed: {result}")
    return json.loads(output.getvalue())


def billing_response(request, timeout):
    """Only replace HTTP response bodies; real billing/cache logic stays active."""
    assert timeout == 15
    assert request.headers["Authorization"] == "Bearer fixture-no-secret"
    path = urlparse(request.full_url).path
    if path == "/v1/accounts":
        return {"accounts": [{"name": "accounts/fixture"}]}
    if path.endswith("/billingUsage"):
        return {"serverlessCosts": []}
    if path.endswith(":getBalance"):
        return {"balance": {"units": "7", "nanos": 500000000}}
    raise AssertionError(f"unexpected billing request: {path}")


records = {"missing": collect("codex")}
# A private executable is the entire Codex app-server I/O boundary. It cannot
# contact a server and accepts only the protocol methods the collector uses.
binary = private / "bin/codex"
binary.parent.mkdir()
binary.write_text(f"#!{sys.executable}\n" + '''import json, os, sys, time
for line in sys.stdin:
    message = json.loads(line)
    if "id" not in message:
        continue
    method = message.get("method")
    answer = {"id": message["id"]}
    if method == "account/read":
        answer["result"] = {"account": {"planType": "pro"}}
    elif method == "account/rateLimits/read":
        if os.environ.get("FIXTURE_LIMITS_FAIL") == "1":
            answer["error"] = {"code": -32603, "message": "failed to fetch codex rate limits"}
        else:
            answer["result"] = {"rateLimits": {"planType": "pro", "primary": {"usedPercent": 40, "windowDurationMins": 300, "resetsAt": int(time.time()) + 3600}}}
    elif method == "initialize":
        answer["result"] = {}
    else:
        raise RuntimeError("unexpected RPC: " + method)
    print(json.dumps(answer), flush=True)
''')
binary.chmod(0o755)
# Plain and compressed copies of the SAME rollout exercise the actual host's
# compression-swap deduplication, not synthetic aggregate counters.
from compression import zstd  # noqa: E402
stamp = datetime.now(timezone.utc).isoformat()
rollout = private / ".codex/sessions/rollout-fixture.jsonl"
rollout.parent.mkdir(parents=True)
lines = [
    {"type": "session_meta", "payload": {"id": "fixture", "model_provider": "openai"}},
    {"type": "turn_context", "payload": {"model": "gpt-fixture"}},
    {"type": "event_msg", "payload": {"type": "token_count", "info": {
        "last_token_usage": {"input_tokens": 7, "output_tokens": 2},
        "total_token_usage": {"input_tokens": 7, "output_tokens": 2}}}},
]
content = "\n".join(json.dumps({"timestamp": stamp, **line}) for line in lines) + "\n"
packed = rollout.with_suffix(".jsonl.zst")
packed.write_bytes(zstd.compress(content.encode()))
records["compressed"] = collect("codex")
rollout.write_text(content)
records["swapping"] = collect("codex")
claims = base64.urlsafe_b64encode(json.dumps({"https://api.openai.com/auth": {"chatgpt_user_id": "fixture-user"}}).encode()).decode().rstrip("=")
write(private / ".codex/auth.json", {"tokens": {"account_id": "fixture", "id_token": "fixture." + claims + ".signature"}})
records["subscription"] = collect("codex")
os.environ["FIXTURE_LIMITS_FAIL"] = "1"
records["stale"] = collect("codex")
os.environ.pop("FIXTURE_LIMITS_FAIL")
# Registered accounts travel through the real collector's account_entry path.
write(private / ".local/state/omarchy/agents/accounts/codex.json", {
    "active": "main", "accounts": [
        {"id": "main", "label": "Main", "primary": True},
        {"id": "work", "label": "Work", "home": str(private / ".codex")},
    ],
})
collect("codex")
os.environ["FIXTURE_LIMITS_FAIL"] = "1"
records["accounts"] = collect("codex")
os.environ["FIREWORKS_API_KEY"] = "fixture-no-secret"
write(private / ".config/omarchy/agents/fireworks.json", {"fundedAmount": 10})
records["prepaid"] = collect("fireworks")
for name in ("compressed", "swapping"):
    assert records[name]["totalSessions"] == 1, records[name]
    assert records[name]["modelUsage"]["gpt-fixture"]["inputTokens"] == 7
assert records["stale"]["limitsStale"] and records["stale"]["authHelpText"]
assert all(account["stale"] for account in records["accounts"]["accounts"]), records["accounts"]
assert records["prepaid"]["balance"]["remaining"] == 7.5
write(out, records)
print("provider collectors: captured missing, compressed, swapping, subscription, stale, accounts and prepaid records without network")
