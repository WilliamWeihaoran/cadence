#!/usr/bin/env python3
"""Minimal stdio smoke test for the repo-local Cadence MCP server."""

from __future__ import annotations

import json
import os
import select
import subprocess
import sys
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
PLUGIN_DIR = SCRIPT_DIR.parent
LAUNCHER = SCRIPT_DIR / "run-cadence-mcp.sh"
EXPECTED_TOOLS = {
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
}


def main() -> int:
    date_arg = sys.argv[1] if len(sys.argv) > 1 else None
    process = subprocess.Popen(
        [str(LAUNCHER)],
        cwd=PLUGIN_DIR,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
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

        server_info = initialize["result"]["serverInfo"]
        print(f"OK {server_info['name']} {server_info['version']}")
        print(f"OK tools/list {len(tool_names)} tools")
        print(f"OK get_today_brief dateKey={brief['dateKey']}")
        print("OK tool error paths")
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"SMOKE FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
