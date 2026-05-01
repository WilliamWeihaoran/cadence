#!/usr/bin/env python3
"""Minimal stdio smoke test for the repo-local Cadence MCP server."""

from __future__ import annotations

import json
import os
import select
import subprocess
import sys
import tempfile
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
PLUGIN_DIR = SCRIPT_DIR.parent
LAUNCHER = SCRIPT_DIR / "run-cadence-mcp.sh"
EXPECTED_TOOLS = {
    "mcp_diagnostics",
    "get_today_brief",
    "list_tasks",
    "get_task",
    "list_task_bundles",
    "get_task_bundle",
    "list_containers",
    "get_container_summary",
    "list_tags",
    "get_core_notes",
    "list_notes",
    "get_note",
    "list_documents",
    "get_document",
    "list_goals",
    "get_goal",
    "list_habits",
    "list_links",
    "search_cadence",
    "get_recent_mcp_writes",
    "create_task",
    "update_task",
    "schedule_task",
    "complete_task",
    "reopen_task",
    "cancel_task",
    "bulk_cancel_tasks",
    "append_core_note",
}


def prepare_fixture_store() -> tempfile.TemporaryDirectory:
    return tempfile.TemporaryDirectory(prefix="cadence-mcp-smoke-")


def main() -> int:
    date_arg = sys.argv[1] if len(sys.argv) > 1 else None
    temp_store = prepare_fixture_store()
    env = os.environ.copy()
    env["CADENCE_MCP_STORE_URL"] = str(Path(temp_store.name) / "default.store")
    env["CADENCE_MCP_CREATE_STORE_IF_MISSING"] = "1"
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
        if diagnostics.get("noteMigrationHealthIssues") != "0":
            raise AssertionError(f"expected clean note migration health, got {diagnostics}")
        audit_log = Path(temp_store.name) / "mcp-audit.log"
        if diagnostics.get("auditLogPath") != str(audit_log):
            raise AssertionError(f"expected audit log path {audit_log}, got {diagnostics.get('auditLogPath')}")

        arguments = {"date": date_arg or "2026-04-28"}
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

        note_date = date_arg or "2026-04-28"
        core_note_marker = f"MCP smoke core note {int(time.time() * 1000)}"
        send(
            {
                "jsonrpc": "2.0",
                "id": 16,
                "method": "tools/call",
                "params": {
                    "name": "append_core_note",
                    "arguments": {
                        "kind": "daily",
                        "date": note_date,
                        "content": core_note_marker,
                        "separator": "\n",
                    },
                },
            }
        )
        append_core_note = read_response(16)
        if append_core_note["result"].get("isError", False):
            raise AssertionError(append_core_note["result"]["content"][0]["text"])
        appended_notes = json.loads(append_core_note["result"]["content"][0]["text"])
        daily_note = appended_notes.get("dailyNote")
        if not daily_note or core_note_marker not in daily_note["content"]:
            raise AssertionError(f"expected appended daily note content, got {appended_notes}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 17,
                "method": "tools/call",
                "params": {"name": "get_core_notes", "arguments": {"date": note_date}},
            }
        )
        get_core_notes = read_response(17)
        if get_core_notes["result"].get("isError", False):
            raise AssertionError(get_core_notes["result"]["content"][0]["text"])
        core_notes = json.loads(get_core_notes["result"]["content"][0]["text"])
        if core_note_marker not in (core_notes.get("dailyNote") or {}).get("content", ""):
            raise AssertionError(f"expected get_core_notes to return appended marker, got {core_notes}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 23,
                "method": "tools/call",
                "params": {"name": "list_notes", "arguments": {"kind": "daily", "query": core_note_marker}},
            }
        )
        list_notes_response = read_response(23)
        if list_notes_response["result"].get("isError", False):
            raise AssertionError(list_notes_response["result"]["content"][0]["text"])
        note_hits = json.loads(list_notes_response["result"]["content"][0]["text"])
        if not any(note["id"] == daily_note["id"] for note in note_hits):
            raise AssertionError(f"expected list_notes to include appended daily note, got {note_hits}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 24,
                "method": "tools/call",
                "params": {"name": "get_note", "arguments": {"noteId": daily_note["id"]}},
            }
        )
        get_note_response = read_response(24)
        if get_note_response["result"].get("isError", False):
            raise AssertionError(get_note_response["result"]["content"][0]["text"])
        note_detail = json.loads(get_note_response["result"]["content"][0]["text"])
        if core_note_marker not in note_detail["content"]:
            raise AssertionError(f"expected get_note content to include marker, got {note_detail}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 18,
                "method": "tools/call",
                "params": {"name": "search_cadence", "arguments": {"query": core_note_marker, "scopes": ["core_notes"]}},
            }
        )
        core_search_response = read_response(18)
        if core_search_response["result"].get("isError", False):
            raise AssertionError(core_search_response["result"]["content"][0]["text"])
        core_search_hits = json.loads(core_search_response["result"]["content"][0]["text"])
        if not any(hit["entityType"] == "daily_note" and hit["entityId"] == daily_note["id"] for hit in core_search_hits):
            raise AssertionError(f"expected core_notes search to find daily note, got {core_search_hits}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 19,
                "method": "tools/call",
                "params": {"name": "search_cadence", "arguments": {"query": core_note_marker}},
            }
        )
        default_search_response = read_response(19)
        if default_search_response["result"].get("isError", False):
            raise AssertionError(default_search_response["result"]["content"][0]["text"])
        default_search_hits = json.loads(default_search_response["result"]["content"][0]["text"])
        if not any(hit["entityType"] == "daily_note" and hit["entityId"] == daily_note["id"] for hit in default_search_hits):
            raise AssertionError(f"expected default search to include core notes, got {default_search_hits}")

        for offset, tool_name in enumerate(["list_tags", "list_goals", "list_habits", "list_links", "list_task_bundles"], start=25):
            send(
                {
                    "jsonrpc": "2.0",
                    "id": offset,
                    "method": "tools/call",
                    "params": {"name": tool_name, "arguments": {"limit": 3}},
                }
            )
            response = read_response(offset)
            if response["result"].get("isError", False):
                raise AssertionError(response["result"]["content"][0]["text"])
            json.loads(response["result"]["content"][0]["text"])

        send(
            {
                "jsonrpc": "2.0",
                "id": 20,
                "method": "tools/call",
                "params": {"name": "list_documents", "arguments": {"limit": 3}},
            }
        )
        list_documents_response = read_response(20)
        if list_documents_response["result"].get("isError", False):
            raise AssertionError(list_documents_response["result"]["content"][0]["text"])
        json.loads(list_documents_response["result"]["content"][0]["text"])

        send(
            {
                "jsonrpc": "2.0",
                "id": 21,
                "method": "tools/call",
                "params": {"name": "get_document", "arguments": {"documentId": "00000000-0000-0000-0000-000000000000"}},
            }
        )
        missing_document_response = read_response(21)
        if not missing_document_response["result"].get("isError", False):
            raise AssertionError("get_document with a missing documentId should return an MCP tool error")

        send(
            {
                "jsonrpc": "2.0",
                "id": 22,
                "method": "tools/call",
                "params": {"name": "search_cadence", "arguments": {"query": "unlikely-meeting-note-marker", "scopes": ["event_notes"]}},
            }
        )
        event_note_search_response = read_response(22)
        if event_note_search_response["result"].get("isError", False):
            raise AssertionError(event_note_search_response["result"]["content"][0]["text"])
        json.loads(event_note_search_response["result"]["content"][0]["text"])

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

        send(
            {
                "jsonrpc": "2.0",
                "id": 13,
                "method": "tools/call",
                "params": {"name": "bulk_cancel_tasks", "arguments": {"titlePrefix": "MCP"}},
            }
        )
        invalid_bulk_prefix = read_response(13)
        if not invalid_bulk_prefix["result"].get("isError", False):
            raise AssertionError("bulk_cancel_tasks with a short titlePrefix should return an MCP tool error")

        send(
            {
                "jsonrpc": "2.0",
                "id": 14,
                "method": "tools/call",
                "params": {"name": "bulk_cancel_tasks", "arguments": {"titlePrefix": "MCP smoke"}},
            }
        )
        bulk_cancel = read_response(14)
        if bulk_cancel["result"].get("isError", False):
            raise AssertionError(bulk_cancel["result"]["content"][0]["text"])
        bulk_cancel_payload = json.loads(bulk_cancel["result"]["content"][0]["text"])
        if len(bulk_cancel_payload["cancelledTasks"]) < 3:
            raise AssertionError(f"expected bulk cancel to cancel smoke tasks, got {bulk_cancel_payload}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 15,
                "method": "tools/call",
                "params": {"name": "get_recent_mcp_writes", "arguments": {"limit": 4}},
            }
        )
        recent_writes_response = read_response(15)
        if recent_writes_response["result"].get("isError", False):
            raise AssertionError(recent_writes_response["result"]["content"][0]["text"])
        recent_writes = json.loads(recent_writes_response["result"]["content"][0]["text"])
        if not recent_writes or recent_writes[0]["tool"] != "bulk_cancel_tasks":
            raise AssertionError(f"expected newest audit entry to be bulk_cancel_tasks, got {recent_writes}")

        if not audit_log.exists():
            raise AssertionError("expected MCP writes to create an audit log")
        audit_entries = [json.loads(line) for line in audit_log.read_text().splitlines() if line.strip()]
        create_audits = [entry for entry in audit_entries if entry["tool"] == "create_task"]
        if len(create_audits) < 3:
            raise AssertionError(f"expected at least 3 create_task audit entries, got {len(create_audits)}")
        bulk_cancel_audits = [entry for entry in audit_entries if entry["tool"] == "bulk_cancel_tasks"]
        if len(bulk_cancel_audits) < 3:
            raise AssertionError(f"expected at least 3 bulk_cancel_tasks audit entries, got {len(bulk_cancel_audits)}")
        if any("MCP smoke invalid duration" in entry["summary"] for entry in audit_entries):
            raise AssertionError("invalid write should not be present in the audit log")

        server_info = initialize["result"]["serverInfo"]
        print(f"OK {server_info['name']} {server_info['version']}")
        print(f"OK tools/list {len(tool_names)} tools")
        print(f"OK diagnostics mode={diagnostics['mode']}")
        print(f"OK get_today_brief dateKey={brief['dateKey']}")
        print("OK core note append/read/search")
        print("OK note list/detail paths")
        print("OK tag/goal/habit/link/bundle list paths")
        print("OK document/event-note read paths")
        print("OK string scheduledStartMin")
        print("OK natural date/duration")
        print("OK word duration")
        print("OK invalid duration error")
        print("OK bulk cancel")
        print("OK recent MCP writes")
        print(f"OK audit log entries={len(audit_entries)}")
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
