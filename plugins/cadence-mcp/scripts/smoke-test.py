#!/usr/bin/env python3
"""Minimal stdio smoke test for the repo-local Cadence MCP server."""

from __future__ import annotations

import datetime
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
WRITE_TOOLS = {
    "create_task",
    "update_task",
    "schedule_task",
    "complete_task",
    "reopen_task",
    "cancel_task",
    "bulk_cancel_tasks",
    "append_core_note",
}
EXPECTED_TOOLS = {
    "mcp_diagnostics",
    "get_today_brief",
    "list_tasks",
    "get_task",
    "list_task_bundles",
    "get_task_bundle",
    "list_contexts",
    "get_context_summary",
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
} | WRITE_TOOLS
READ_ONLY_TOOLS = EXPECTED_TOOLS - WRITE_TOOLS
MISSING_UUID = "00000000-0000-0000-0000-000000000000"

# Every tool name the read-write phase actually dispatches, recorded by `send` and compared
# against the server's own `tools/list` before this script prints OK. This is the guard, not the
# list above it: T-259 was filed because the smoke test dispatched 21 of the router's 30 arms and
# nothing said so, and a coverage claim that lives in a comment goes stale the first time an arm
# is added. The read-only phase deliberately does not record — a `create_task` refused because
# writes are off has exercised the gate, not the arm.
DISPATCHED = set()

# Response DTO shapes, so a renamed or dropped field on a list payload fails here rather than in
# a user's editor. Swift's synthesized `Codable` emits optionals with `encodeIfPresent`, so a nil
# optional is an *absent* key and not a null — which is why `check_keys` takes the optional names
# separately instead of comparing sets outright.
TASK_SUMMARY_KEYS = {
    "id", "title", "status", "priority", "dueDate", "scheduledDate", "scheduledStartMin",
    "estimatedMinutes", "container", "goal", "sectionName", "tags", "isDone", "isCancelled",
}
TASK_SUMMARY_OPTIONAL = {"container", "goal"}
TASK_DETAIL_KEYS = {"summary", "notes", "actualMinutes", "subtasks", "createdAt", "completedAt"}
TASK_DETAIL_OPTIONAL = {"completedAt"}
TAG_SUMMARY_KEYS = {"id", "slug", "name", "colorHex", "description", "isArchived"}
TAG_DETAIL_KEYS = {"summary", "taskCount", "noteCount", "createdAt", "updatedAt"}
NOTE_SUMMARY_KEYS = {"id", "kind", "title", "key", "container", "updatedAt", "excerpt", "tags"}
NOTE_SUMMARY_OPTIONAL = {"key", "container"}


def check_keys(payload: dict, expected: set, optional: set, label: str) -> None:
    actual = set(payload)
    unexpected = sorted(actual - expected)
    missing = sorted(expected - optional - actual)
    if unexpected or missing:
        raise AssertionError(f"{label}: unexpected keys {unexpected}, missing keys {missing}")


def assert_day(actual: str, offset: int, label: str, before: datetime.date) -> None:
    """Accepts the day computed from either side of the call, so a run straddling midnight is not
    a flake. `before` is read before the request; `date.today()` here is read after it."""
    allowed = {
        (before + datetime.timedelta(days=offset)).isoformat(),
        (datetime.date.today() + datetime.timedelta(days=offset)).isoformat(),
    }
    if actual not in allowed:
        raise AssertionError(f"{label}: expected one of {sorted(allowed)}, got {actual}")


def prepare_fixture_store() -> tempfile.TemporaryDirectory:
    return tempfile.TemporaryDirectory(prefix="cadence-mcp-smoke-")


def start_server(env: dict) -> subprocess.Popen:
    return subprocess.Popen(
        [str(LAUNCHER)],
        cwd=PLUGIN_DIR,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env=env,
    )


def send_message(process: subprocess.Popen, message: dict) -> None:
    assert process.stdin is not None
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def read_response(process: subprocess.Popen, expected_id: int, timeout: float = 45.0) -> dict:
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


def initialize_server(process: subprocess.Popen, request_id: int, client_name: str) -> dict:
    send_message(
        process,
        {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": client_name, "version": "0.1.0"},
            },
        },
    )
    initialize = read_response(process, request_id)
    send_message(process, {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
    return initialize


def stop_server(process: subprocess.Popen) -> None:
    process.terminate()
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.kill()


def verify_default_read_only_mode() -> None:
    temp_store = prepare_fixture_store()
    env = os.environ.copy()
    env["CADENCE_MCP_STORE_URL"] = str(Path(temp_store.name) / "default.store")
    env["CADENCE_MCP_CREATE_STORE_IF_MISSING"] = "1"

    try:
        bootstrap_env = env.copy()
        bootstrap_env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        bootstrap = start_server(bootstrap_env)
        try:
            initialize_server(bootstrap, 100, "cadence-mcp-smoke-bootstrap")
        finally:
            stop_server(bootstrap)

        env.pop("CADENCE_MCP_ENABLE_WRITES", None)
        process = start_server(env)
        try:
            initialize_server(process, 101, "cadence-mcp-smoke-read-only")

            send_message(process, {"jsonrpc": "2.0", "id": 102, "method": "tools/list", "params": {}})
            tools = read_response(process, 102)["result"]["tools"]
            tool_names = {tool["name"] for tool in tools}
            missing = sorted(READ_ONLY_TOOLS - tool_names)
            if missing:
                raise AssertionError(f"missing read-only tools: {', '.join(missing)}")
            exposed_writes = sorted(WRITE_TOOLS & tool_names)
            if exposed_writes:
                raise AssertionError(f"default mode exposed write tools: {', '.join(exposed_writes)}")

            send_message(process, {"jsonrpc": "2.0", "id": 103, "method": "tools/call", "params": {"name": "mcp_diagnostics", "arguments": {}}})
            diagnostics_response = read_response(process, 103)
            if diagnostics_response["result"].get("isError", False):
                raise AssertionError(diagnostics_response["result"]["content"][0]["text"])
            diagnostics = json.loads(diagnostics_response["result"]["content"][0]["text"])
            if diagnostics["mode"] != "read-only":
                raise AssertionError(f"expected read-only diagnostics, got {diagnostics}")
            if diagnostics["writeToolCount"] != "0":
                raise AssertionError(f"expected no write tools in default diagnostics, got {diagnostics}")

            send_message(process, {"jsonrpc": "2.0", "id": 104, "method": "tools/call", "params": {"name": "create_task", "arguments": {"title": "blocked"}}})
            blocked_write = read_response(process, 104)
            if not blocked_write["result"].get("isError", False):
                raise AssertionError("create_task should be rejected when write mode is disabled")
        finally:
            stop_server(process)
    finally:
        temp_store.cleanup()


def main() -> int:
    verify_default_read_only_mode()
    print("OK default read-only MCP mode")

    date_arg = sys.argv[1] if len(sys.argv) > 1 else None
    temp_store = prepare_fixture_store()
    env = os.environ.copy()
    env["CADENCE_MCP_STORE_URL"] = str(Path(temp_store.name) / "default.store")
    env["CADENCE_MCP_CREATE_STORE_IF_MISSING"] = "1"
    env["CADENCE_MCP_ENABLE_WRITES"] = "1"
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
        # Recording here rather than at each call site is what makes the coverage check total: a
        # block added later cannot forget to opt in.
        if message.get("method") == "tools/call":
            DISPATCHED.add(message["params"]["name"])
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

    # Named `dispatch`, not `call`: `call` is already a local holding a get_today_brief response
    # further down, and shadowing it fails at runtime as "'dict' object is not callable".
    def dispatch(request_id: int, name: str, arguments: dict = None) -> dict:
        send({
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments if arguments is not None else {}},
        })
        return read_response(request_id)

    def call_ok(request_id: int, name: str, arguments: dict = None):
        response = dispatch(request_id, name, arguments)
        if response["result"].get("isError", False):
            raise AssertionError(f"{name}: {response['result']['content'][0]['text']}")
        return json.loads(response["result"]["content"][0]["text"])

    def call_error(request_id: int, name: str, arguments: dict, why: str, expects: str = None) -> str:
        response = dispatch(request_id, name, arguments)
        if not response["result"].get("isError", False):
            raise AssertionError(f"{name} should have returned an MCP tool error: {why}")
        message = response["result"]["content"][0]["text"]
        # Asserting the message and not just `isError` is what gives an error-path check teeth. A
        # deleted router arm answers "Unknown tool", a renamed argument key answers a different
        # "Missing required argument", and a bare `isError` check is green for both — which is how
        # an arm can be "covered" by a call that never reaches it.
        if expects is not None and expects not in message:
            raise AssertionError(f"{name}: expected an error mentioning {expects!r}, got {message!r}")
        return message

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
        if diagnostics.get("supportsFlexibleStringArrays") != "true":
            raise AssertionError(f"expected flexible string arrays support, got {diagnostics}")
        if diagnostics.get("noteMigrationHealthIssues") != "0":
            raise AssertionError(f"expected clean note migration health, got {diagnostics}")
        audit_log = Path(temp_store.name) / "mcp-audit.log"
        if diagnostics.get("auditLogPath") != str(audit_log):
            raise AssertionError(f"expected audit log path {audit_log}, got {diagnostics.get('auditLogPath')}")
        if diagnostics.get("storePath") != str(Path(temp_store.name) / "default.store"):
            raise AssertionError(f"expected store path in diagnostics, got {diagnostics}")

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
                "id": 26,
                "method": "tools/call",
                "params": {"name": "list_contexts", "arguments": {"limit": 3}},
            }
        )
        list_contexts_response = read_response(26)
        if list_contexts_response["result"].get("isError", False):
            raise AssertionError(list_contexts_response["result"]["content"][0]["text"])
        context_hits = json.loads(list_contexts_response["result"]["content"][0]["text"])
        if context_hits != []:
            raise AssertionError(f"expected empty contexts in fresh store, got {context_hits}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 27,
                "method": "tools/call",
                "params": {
                    "name": "get_context_summary",
                    "arguments": {"contextId": "00000000-0000-0000-0000-000000000000"},
                },
            }
        )
        missing_context = read_response(27)
        if not missing_context["result"].get("isError", False):
            raise AssertionError("get_context_summary with a missing contextId should return an MCP tool error")

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
                "params": {"name": "search_cadence", "arguments": {"query": core_note_marker, "scopes": "core_notes"}},
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
                "id": 28,
                "method": "tools/call",
                "params": {
                    "name": "create_task",
                    "arguments": {
                        "title": "MCP smoke flexible arrays",
                        "tagNames": "alpha, beta",
                        "subtaskTitles": "first subtask\nsecond subtask",
                    },
                },
            }
        )
        create_with_flexible_arrays = read_response(28)
        if create_with_flexible_arrays["result"].get("isError", False):
            raise AssertionError(create_with_flexible_arrays["result"]["content"][0]["text"])
        flexible_task = json.loads(create_with_flexible_arrays["result"]["content"][0]["text"])
        if len(flexible_task["summary"]["tags"]) != 2:
            raise AssertionError(f"expected tagNames string to resolve two tags, got {flexible_task}")
        if len(flexible_task["subtasks"]) != 2:
            raise AssertionError(f"expected subtaskTitles string to resolve two subtasks, got {flexible_task}")

        send(
            {
                "jsonrpc": "2.0",
                "id": 29,
                "method": "tools/call",
                "params": {
                    "name": "list_tasks",
                    "arguments": {
                        "status": "todo",
                        "tagSlugs": "alpha, beta",
                        "limit": 10,
                    },
                },
            }
        )
        flexible_list_response = read_response(29)
        if flexible_list_response["result"].get("isError", False):
            raise AssertionError(flexible_list_response["result"]["content"][0]["text"])
        flexible_list = json.loads(flexible_list_response["result"]["content"][0]["text"])
        if not any(task["id"] == flexible_task["summary"]["id"] for task in flexible_list):
            raise AssertionError(f"expected list_tasks flexible filters to return created task, got {flexible_list}")

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
                "id": 30,
                "method": "tools/call",
                "params": {"name": "list_tags", "arguments": {"limit": "many"}},
            }
        )
        invalid_limit = read_response(30)
        if not invalid_limit["result"].get("isError", False):
            raise AssertionError("list_tags with a non-integer limit should return an MCP tool error")

        # --- Read arms nothing had ever dispatched (T-259) ------------------------------
        # A fresh fixture store holds no bundles, containers or goals, and MCP has no tool that
        # creates one, so what these can establish is the argument wiring and the not-found path.
        # That is not nothing: `bundleId`, `goalId` and `containerKind`+`containerId` are each
        # read by exactly one arm, so a renamed key here fails nowhere else. Each asserts the
        # error *message*, because "Unknown tool" is also an error.
        call_error(40, "get_task_bundle", {}, "missing bundleId", "Missing required argument: bundleId")
        call_error(
            41,
            "get_task_bundle",
            {"bundleId": MISSING_UUID},
            "unknown bundleId",
            f"No task bundle found with id {MISSING_UUID}.",
        )

        containers = call_ok(42, "list_containers", {"limit": 3})
        if containers != []:
            raise AssertionError(f"expected no containers in a fresh store, got {containers}")
        call_error(43, "list_containers", {"kind": "folder"}, "invalid container kind", "Invalid container kind: folder")

        call_error(
            44,
            "get_container_summary",
            {"containerId": MISSING_UUID},
            "missing containerKind",
            "Missing required argument: containerKind",
        )
        call_error(
            45,
            "get_container_summary",
            {"containerKind": "project", "containerId": MISSING_UUID},
            "unknown container",
            f"No project found with id {MISSING_UUID}.",
        )

        call_error(46, "get_goal", {}, "missing goalId", "Missing required argument: goalId")
        call_error(
            47,
            "get_goal",
            {"goalId": MISSING_UUID},
            "unknown goalId",
            f"No goal found with id {MISSING_UUID}.",
        )

        # --- The five write tools that ran nowhere at all (T-259) ------------------------
        # `update_task`, `schedule_task`, `complete_task`, `reopen_task` and `cancel_task` are
        # five of the eight write tools and had no execution path in this file or in any test.
        # Each carries its own argument wiring, and `schedule_task` is the only arm that reads
        # `minuteOfDay`, `durationMinutes` and `clearScheduledDate` together — a reordered
        # `CadenceScheduleTaskOptions` initialiser would compile, advertise itself, and go wrong
        # only in the user's store. The probe stays outside the `MCP smoke` title prefix so the
        # bulk-cancel counts below keep meaning what they meant before.
        probe = call_ok(50, "create_task", {"title": "Coverage probe lifecycle", "estimatedMinutes": 25})
        check_keys(probe, TASK_DETAIL_KEYS, TASK_DETAIL_OPTIONAL, "create_task detail")
        check_keys(probe["summary"], TASK_SUMMARY_KEYS, TASK_SUMMARY_OPTIONAL, "create_task summary")
        probe_id = probe["summary"]["id"]

        before = datetime.date.today()
        updated = call_ok(
            51,
            "update_task",
            {
                "taskId": probe_id,
                "title": "Coverage probe lifecycle (updated)",
                "notes": "probe notes",
                "priority": "high",
                "dueDate": "today",
                "estimatedMinutes": "45m",
                "tagNames": "coverage-alpha, coverage-beta",
            },
        )
        if updated["summary"]["title"] != "Coverage probe lifecycle (updated)":
            raise AssertionError(f"expected update_task to rewrite the title, got {updated['summary']}")
        if updated["notes"] != "probe notes":
            raise AssertionError(f"expected update_task to write notes, got {updated}")
        if updated["summary"]["priority"] != "high":
            raise AssertionError(f"expected update_task to set priority, got {updated['summary']}")
        assert_day(updated["summary"]["dueDate"], 0, "update_task dueDate", before)
        if updated["summary"]["estimatedMinutes"] != 45:
            raise AssertionError(f"expected 45m to parse to 45, got {updated['summary']}")
        if len(updated["summary"]["tags"]) != 2:
            raise AssertionError(f"expected two tags on the updated task, got {updated['summary']}")

        cleared_due = call_ok(52, "update_task", {"taskId": probe_id, "clearDueDate": True})
        if cleared_due["summary"]["dueDate"] != "":
            raise AssertionError(f"expected clearDueDate to empty the due date, got {cleared_due['summary']}")
        call_error(
            53,
            "update_task",
            {"taskId": probe_id, "dueDate": "today", "clearDueDate": True},
            "clearDueDate combined with dueDate",
            "clearDueDate cannot be combined with dueDate.",
        )
        call_error(54, "update_task", {"taskId": probe_id}, "no fields to change", "No valid changes were provided.")

        before = datetime.date.today()
        scheduled = call_ok(
            55,
            "schedule_task",
            {
                "taskId": probe_id,
                "scheduledDate": "today",
                "scheduledStartMin": "4:30 pm",
                "estimatedMinutes": "1.5h",
            },
        )["summary"]
        assert_day(scheduled["scheduledDate"], 0, "schedule_task scheduledDate", before)
        if scheduled["scheduledStartMin"] != 990:
            raise AssertionError(f"expected 4:30 pm to parse to 990, got {scheduled}")
        if scheduled["estimatedMinutes"] != 90:
            raise AssertionError(f"expected 1.5h to parse to 90, got {scheduled}")
        call_error(
            56,
            "schedule_task",
            {"taskId": probe_id, "scheduledStartMin": "9 am"},
            "scheduledStartMin without scheduledDate",
            "scheduledDate is required when scheduledStartMin is provided.",
        )
        call_error(
            57,
            "schedule_task",
            {"taskId": probe_id, "clearScheduledDate": True, "scheduledDate": "today"},
            "clearScheduledDate combined with scheduledDate",
            "clearScheduledDate cannot be combined with scheduledDate",
        )
        unscheduled = call_ok(58, "schedule_task", {"taskId": probe_id, "clearScheduledDate": True})["summary"]
        if unscheduled["scheduledDate"] != "" or unscheduled["scheduledStartMin"] != -1:
            raise AssertionError(f"expected clearScheduledDate to free the slot, got {unscheduled}")

        completed = call_ok(59, "complete_task", {"taskId": probe_id})
        check_keys(completed, {"task", "spawnedRecurringTask"}, {"spawnedRecurringTask"}, "complete_task result")
        if completed["task"]["summary"]["status"] != "done" or not completed["task"]["summary"]["isDone"]:
            raise AssertionError(f"expected complete_task to finish the task, got {completed['task']['summary']}")
        if completed.get("spawnedRecurringTask") is not None:
            raise AssertionError("a non-recurring task must not spawn an occurrence")

        reopened = call_ok(60, "reopen_task", {"taskId": probe_id})
        if reopened["summary"]["status"] != "todo" or reopened["summary"]["isDone"]:
            raise AssertionError(f"expected reopen_task to return the task to todo, got {reopened['summary']}")
        if reopened.get("completedAt") is not None:
            raise AssertionError(f"expected reopen_task to clear completedAt, got {reopened}")

        cancelled = call_ok(61, "cancel_task", {"taskId": probe_id})
        # Shape first, then state: `cancel_task` and `complete_task` differ by one word at the
        # call site and return *different* DTOs, so checking the keys is what turns that
        # copy-paste into a legible failure rather than a KeyError.
        check_keys(cancelled, TASK_DETAIL_KEYS, TASK_DETAIL_OPTIONAL, "cancel_task detail")
        if cancelled["summary"]["status"] != "cancelled" or not cancelled["summary"]["isCancelled"]:
            raise AssertionError(f"expected cancel_task to cancel the task, got {cancelled['summary']}")
        call_error(
            62,
            "complete_task",
            {"taskId": probe_id},
            "completing a cancelled task",
            f"Cancelled task {probe_id} cannot be completed.",
        )
        call_error(
            63,
            "complete_task",
            {"taskId": MISSING_UUID},
            "unknown taskId",
            f"No task found with id {MISSING_UUID}.",
        )

        # --- Natural language, past the one sample per helper ----------------------------
        # `dateKey`, `durationMinutes` and `minuteOfDay` were each exercised at a single point
        # ("tomorrow", "1h"/"three hours", "4 PM"), so every other branch of their parsers was
        # unrun. The rejections matter as much as the successes: a parser that silently returns
        # nil turns a mistyped argument into a task with no date rather than an error.
        for index, (offset, phrase) in enumerate(
            [(0, "today"), (-1, "yesterday"), (3, "in 3 days"), (2, "+2 days"), (-2, "2 days ago")]
        ):
            before = datetime.date.today()
            parsed = call_ok(
                64 + index,
                "create_task",
                {"title": f"Coverage probe date {phrase}", "scheduledDate": phrase},
            )["summary"]
            assert_day(parsed["scheduledDate"], offset, f"scheduledDate {phrase}", before)
        call_error(
            69,
            "create_task",
            {"title": "Coverage probe bad date", "scheduledDate": "next tuesday"},
            "unparseable relative date",
            "Invalid scheduledDate: next tuesday",
        )

        for index, (phrase, minutes) in enumerate(
            [("30m", 30), ("1.5h", 90), ("45 minutes", 45), ("two and a half hours", 150)]
        ):
            parsed = call_ok(
                70 + index,
                "create_task",
                {"title": f"Coverage probe duration {phrase}", "estimatedMinutes": phrase},
            )["summary"]
            if parsed["estimatedMinutes"] != minutes:
                raise AssertionError(f"expected {phrase} to parse to {minutes}, got {parsed['estimatedMinutes']}")

        for index, (phrase, minute_of_day) in enumerate([("12 am", 0), ("12 pm", 720), ("11:05 AM", 665)]):
            parsed = call_ok(
                74 + index,
                "create_task",
                {
                    "title": f"Coverage probe time {phrase}",
                    "scheduledDate": "today",
                    "scheduledStartMin": phrase,
                },
            )["summary"]
            if parsed["scheduledStartMin"] != minute_of_day:
                raise AssertionError(f"expected {phrase} to parse to {minute_of_day}, got {parsed['scheduledStartMin']}")
        call_error(
            77,
            "create_task",
            {"title": "Coverage probe bad time", "scheduledDate": "today", "scheduledStartMin": "13 pm"},
            "hour outside the 12-hour clock",
            "Invalid scheduledStartMin: 13 pm",
        )

        # --- List DTO shapes -------------------------------------------------------------
        # The `list_*` arms this file already called ran against an empty store and returned
        # `[]`, so no list payload's shape had ever been observed. Tags are seeded when the
        # read-write container opens, and tasks and notes exist by now, so those three can be
        # checked against real rows. Bundles, goals, habits, links, contexts and containers have
        # no MCP creation path and stay empty here — that half of the gap is still open.
        tag_details = call_ok(78, "list_tags", {"limit": 50})
        if not tag_details:
            raise AssertionError("expected seeded default tags in the fixture store")
        check_keys(tag_details[0], TAG_DETAIL_KEYS, set(), "list_tags element")
        check_keys(tag_details[0]["summary"], TAG_SUMMARY_KEYS, set(), "list_tags summary")

        task_rows = call_ok(79, "list_tasks", {"limit": 50, "includeCompleted": True})
        if not task_rows:
            raise AssertionError("expected the created probe tasks in list_tasks")
        check_keys(task_rows[0], TASK_SUMMARY_KEYS, TASK_SUMMARY_OPTIONAL, "list_tasks element")

        note_rows = call_ok(80, "list_notes", {"limit": 10})
        if not note_rows:
            raise AssertionError("expected the appended daily note in list_notes")
        check_keys(note_rows[0], NOTE_SUMMARY_KEYS, NOTE_SUMMARY_OPTIONAL, "list_notes element")

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
        if len(create_audits) < 4:
            raise AssertionError(f"expected at least 4 create_task audit entries, got {len(create_audits)}")
        bulk_cancel_audits = [entry for entry in audit_entries if entry["tool"] == "bulk_cancel_tasks"]
        if len(bulk_cancel_audits) < 3:
            raise AssertionError(f"expected at least 3 bulk_cancel_tasks audit entries, got {len(bulk_cancel_audits)}")
        if any("MCP smoke invalid duration" in entry["summary"] for entry in audit_entries):
            raise AssertionError("invalid write should not be present in the audit log")
        # The audit log is the write path's only record, so a tool that mutates without landing
        # here is a write with no trace.
        audited_tools = {entry["tool"] for entry in audit_entries}
        unaudited = sorted(WRITE_TOOLS - audited_tools)
        if unaudited:
            raise AssertionError(f"write tools that mutated without an audit entry: {', '.join(unaudited)}")

        undispatched = sorted(tool_names - DISPATCHED)
        if undispatched:
            raise AssertionError(f"tools advertised but never dispatched: {', '.join(undispatched)}")

        server_info = initialize["result"]["serverInfo"]
        print(f"OK {server_info['name']} {server_info['version']}")
        print(f"OK tools/list {len(tool_names)} tools")
        print(f"OK diagnostics mode={diagnostics['mode']}")
        print(f"OK get_today_brief dateKey={brief['dateKey']}")
        print("OK core note append/read/search")
        print("OK note list/detail paths")
        print("OK context list/error paths")
        print("OK tag/goal/habit/link/bundle list paths")
        print("OK document/event-note read paths")
        print("OK string scheduledStartMin")
        print("OK natural date/duration")
        print("OK word duration")
        print("OK flexible string arrays")
        print("OK invalid duration error")
        print("OK strict integer validation")
        print("OK bulk cancel")
        print("OK recent MCP writes")
        print(f"OK audit log entries={len(audit_entries)}")
        print("OK tool error paths")
        print("OK write lifecycle update/schedule/complete/reopen/cancel")
        print("OK bundle/container/goal read arms")
        print("OK natural date/duration/time parsing branches")
        print("OK list DTO shapes")
        print(f"OK dispatched {len(DISPATCHED)}/{len(tool_names)} advertised tools")
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
