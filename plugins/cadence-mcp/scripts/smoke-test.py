#!/usr/bin/env python3
"""Minimal stdio smoke test for the repo-local Cadence MCP server."""

from __future__ import annotations

import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
PLUGIN_DIR = SCRIPT_DIR.parent
LAUNCHER = SCRIPT_DIR / "run-cadence-mcp.sh"
REAL_STORE = Path.home() / "Library/Containers/com.haoranwei.Cadence/Data/Library/Application Support/default.store"
EXPECTED_TOOLS = {
    "mcp_diagnostics",
    "get_today_brief",
    "list_tasks",
    "get_task",
    "list_containers",
    "get_container_summary",
    "get_core_notes",
    "list_documents",
    "get_document",
    "search_cadence",
    "get_blocked_tasks",
    "create_task",
    "update_task",
    "schedule_task",
    "complete_task",
    "reopen_task",
    "cancel_task",
    "append_core_note",
}


def prepare_store_copy() -> tempfile.TemporaryDirectory:
    temp_dir = tempfile.TemporaryDirectory(prefix="cadence-mcp-smoke-")
    source = REAL_STORE if REAL_STORE.exists() else Path.home() / "Library/Application Support/default.store"
    if not source.exists():
        temp_dir.cleanup()
        raise FileNotFoundError(f"Could not find Cadence store at {REAL_STORE} or fallback Application Support path")

    destination = Path(temp_dir.name) / "default.store"
    shutil.copy2(source, destination)
    for suffix in ("-shm", "-wal"):
        sidecar = Path(str(source) + suffix)
        if sidecar.exists():
            shutil.copy2(sidecar, Path(str(destination) + suffix))
    return temp_dir


def main() -> int:
    date_arg = sys.argv[1] if len(sys.argv) > 1 else None
    temp_store = prepare_store_copy()
    env = os.environ.copy()
    env["CADENCE_MCP_STORE_URL"] = str(Path(temp_store.name) / "default.store")
    process = subprocess.Popen(
        [str(LAUNCHER)],
        cwd=PLUGIN_DIR,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env=env,
    )

    def send(message: dict) -> None:
        assert process.stdin is not None
        process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        process.stdin.flush()

    def read_response(expected_id: int, timeout: float = 45.0) -> dict:
        assert process.stdout is not None
        assert process.stderr is not None
        deadline = time.time() + timeout

        while time.time() < deadline:
            ready, _, _ = select.select([process.stdout, process.stderr], [], [], 0.1)
            for stream in ready:
                line = stream.readline()
                if not line:
                    continue
                if stream is process.stderr:
                    continue
                payload = json.loads(line)
                if payload.get("id") == expected_id:
                    return payload

            if process.poll() is not None:
                stderr = process.stderr.read()
                raise RuntimeError(f"server exited {process.returncode}: {stderr}")

        raise TimeoutError(f"timed out waiting for response {expected_id}")

    try:
        send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "clientInfo": {"name": "cadence-mcp-smoke", "version": "0.1.0"},
                },
            }
        )
        initialize = read_response(1)
        send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools = read_response(2)["result"]["tools"]
        tool_names = {tool["name"] for tool in tools}
        missing = sorted(EXPECTED_TOOLS - tool_names)
        if missing:
            raise AssertionError(f"missing tools: {', '.join(missing)}")

        send({"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "mcp_diagnostics", "arguments": {}}})
        diagnostics_response = read_response(9)
        if diagnostics_response["result"].get("isError", False):
            raise AssertionError(diagnostics_response["result"]["content"][0]["text"])
        diagnostics = json.loads(diagnostics_response["result"]["content"][0]["text"])
        if diagnostics["mode"] != "read-write":
            raise AssertionError(f"expected read-write diagnostics, got {diagnostics}")

        arguments = {"date": date_arg} if date_arg else {}
        send(
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "get_today_brief", "arguments": arguments},
            }
        )
        call = read_response(3)
        if call["result"].get("isError", False):
            raise AssertionError(call["result"]["content"][0]["text"])

        brief = json.loads(call["result"]["content"][0]["text"])

        send({"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "get_task", "arguments": {}}})
        missing_id = read_response(4)
        if not missing_id["result"].get("isError", False):
            raise AssertionError("get_task without taskId should return an MCP tool error")

        send(
            {
                "jsonrpc": "2.0",
                "id": 5,
                "method": "tools/call",
                "params": {"name": "search_cadence", "arguments": {"query": "cadence", "scopes": ["events"]}},
            }
        )
        invalid_scope = read_response(5)
        if not invalid_scope["result"].get("isError", False):
            raise AssertionError("search_cadence with invalid scope should return an MCP tool error")

        send({"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "create_task", "arguments": {}}})
        missing_title = read_response(6)
        if not missing_title["result"].get("isError", False):
            raise AssertionError("create_task without title should return an MCP tool error")

        send(
            {
                "jsonrpc": "2.0",
                "id": 7,
                "method": "tools/call",
                "params": {"name": "append_core_note", "arguments": {"kind": "events", "content": "nope"}},
            }
        )
        invalid_note_kind = read_response(7)
        if not invalid_note_kind["result"].get("isError", False):
            raise AssertionError("append_core_note with invalid kind should return an MCP tool error")

        send(
            {
                "jsonrpc": "2.0",
                "id": 8,
                "method": "tools/call",
                "params": {
                    "name": "create_task",
                    "arguments": {
                        "title": "MCP smoke string time",
                        "scheduledDate": date_arg or "2026-04-28",
                        "scheduledStartMin": "4 PM",
                    },
                },
            }
        )
        create_with_string_time = read_response(8)
        if create_with_string_time["result"].get("isError", False):
            raise AssertionError(create_with_string_time["result"]["content"][0]["text"])
        task = json.loads(create_with_string_time["result"]["content"][0]["text"])
        if task["summary"]["scheduledStartMin"] != 960:
            raise AssertionError(f"expected 4 PM to parse to 960, got {task['summary']['scheduledStartMin']}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 10,
                "method": "tools/call",
                "params": {
                    "name": "create_task",
                    "arguments": {
                        "title": "MCP smoke natural date duration",
                        "scheduledDate": "tomorrow",
                        "estimatedMinutes": "1h",
                    },
                },
            }
        )
        create_with_natural_inputs = read_response(10)
        if create_with_natural_inputs["result"].get("isError", False):
            raise AssertionError(create_with_natural_inputs["result"]["content"][0]["text"])
        natural_task = json.loads(create_with_natural_inputs["result"]["content"][0]["text"])
        if natural_task["summary"]["scheduledDate"] == "tomorrow":
            raise AssertionError("expected tomorrow to be normalized to a date key")
        if natural_task["summary"]["estimatedMinutes"] != 60:
            raise AssertionError(f"expected 1h to parse to 60, got {natural_task['summary']['estimatedMinutes']}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 11,
                "method": "tools/call",
                "params": {
                    "name": "create_task",
                    "arguments": {
                        "title": "MCP smoke word duration",
                        "estimatedMinutes": "three hours",
                    },
                },
            }
        )
        create_with_word_duration = read_response(11)
        if create_with_word_duration["result"].get("isError", False):
            raise AssertionError(create_with_word_duration["result"]["content"][0]["text"])
        word_duration_task = json.loads(create_with_word_duration["result"]["content"][0]["text"])
        if word_duration_task["summary"]["estimatedMinutes"] != 180:
            raise AssertionError(f"expected three hours to parse to 180, got {word_duration_task['summary']['estimatedMinutes']}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 12,
                "method": "tools/call",
                "params": {
                    "name": "create_task",
                    "arguments": {
                        "title": "MCP smoke invalid duration",
                        "estimatedMinutes": "forever",
                    },
                },
            }
        )
        invalid_duration = read_response(12)
        if not invalid_duration["result"].get("isError", False):
            raise AssertionError("create_task with invalid duration should return an MCP tool error")

        server_info = initialize["result"]["serverInfo"]
        print(f"OK {server_info['name']} {server_info['version']}")
        print(f"OK tools/list {len(tool_names)} tools")
        print(f"OK diagnostics mode={diagnostics['mode']}")
        print(f"OK get_today_brief dateKey={brief['dateKey']}")
        print("OK string scheduledStartMin")
        print("OK natural date/duration")
        print("OK word duration")
        print("OK invalid duration error")
        print("OK tool error paths")
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
        temp_store.cleanup()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"SMOKE FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
