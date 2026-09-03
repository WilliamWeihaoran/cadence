#!/usr/bin/env python3
"""Seed a PRIVATE Cadence store with presentable data for App Store screenshots.

This never touches the user's real store. It drives `CadenceMCPServer` over stdio
against an explicit `CADENCE_MCP_STORE_URL`, which must be a throwaway path --
by convention the same one `scripts/run-macos-app.sh` gives the app:

    $TMPDIR/CadenceUITestStores/<id>/default.store

Usage:

    python3 docs/screenshots/seed-screenshot-data.py \
        --server <derived-data>/Build/Products/Debug/CadenceMCPServer \
        --store  "$TMPDIR/CadenceUITestStores/shots/default.store"

Run it BEFORE launching the app, then launch with the matching store id:

    ./scripts/run-macos-app.sh start <...>/Cadence.app shots

The MCP write surface can create tasks and append to daily/weekly/permanent
notes. It cannot create contexts, areas or projects, so the Lists/Kanban angle
still needs the few UI steps written down in docs/screenshots/README.md.
"""

import argparse
import datetime as dt
import json
import os
import subprocess
import sys

REFUSED_SUBSTRINGS = (
    "Library/Containers/com.haoranwei.Cadence",
    "Library/Application Support/Cadence",
)


class MCPClient:
    def __init__(self, server: str, store: str) -> None:
        env = dict(os.environ)
        env["CADENCE_MCP_STORE_URL"] = store
        env["CADENCE_MCP_CREATE_STORE_IF_MISSING"] = "1"
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        os.makedirs(os.path.dirname(store), exist_ok=True)
        self.proc = subprocess.Popen(
            [server],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True,
            bufsize=1,
        )
        self.counter = 0
        self._rpc(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "cadence-screenshot-seed", "version": "1"},
            },
        )
        self._notify("notifications/initialized", {})

    def _notify(self, method: str, params: dict) -> None:
        self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method, "params": params}) + "\n")
        self.proc.stdin.flush()

    def _rpc(self, method: str, params: dict) -> dict:
        self.counter += 1
        payload = {"jsonrpc": "2.0", "id": self.counter, "method": method, "params": params}
        self.proc.stdin.write(json.dumps(payload) + "\n")
        self.proc.stdin.flush()
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("CadenceMCPServer closed: " + self.proc.stderr.read())
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if message.get("id") == self.counter:
                return message

    def call(self, name: str, arguments: dict | None = None):
        message = self._rpc("tools/call", {"name": name, "arguments": arguments or {}})
        if "error" in message:
            raise RuntimeError(f"{name} failed: {message['error']}")
        result = message.get("result", {})
        text = "\n".join(part.get("text", "") for part in result.get("content", []) if part.get("type") == "text")
        if result.get("isError"):
            raise RuntimeError(f"{name} returned an error: {text}")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text

    def close(self) -> None:
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


def day(offset: int) -> str:
    return (dt.date.today() + dt.timedelta(days=offset)).strftime("%Y-%m-%d")


# (title, day offset, start minutes or None, estimate or None, priority, tags, notes)
TODAY_TASKS = [
    ("Rewrite the onboarding empty state", 0, 9 * 60, 45, "high", ["design"],
     "The first-run screen still explains the sidebar instead of the first thing to do."),
    ("Design review: weekly planner", 0, 10 * 60 + 30, 60, "medium", ["design"], ""),
    ("Reply to the accessibility audit notes", 0, 12 * 60, 20, "medium", ["writing"], ""),
    ("Cut the 1.0 release branch", 0, 14 * 60, 90, "high", ["release"],
     "Tag, changelog, then hand the build to TestFlight."),
    ("Plan next week", 0, 16 * 60 + 30, 30, "low", ["planning"], ""),
]

DONE_TODAY = [
    ("Triage overnight crash reports", 0, 8 * 60, 25, "medium", ["release"], ""),
    ("Stand-up", 0, 9 * 60 + 45, 15, "none", [], ""),
]

WEEK_TASKS = [
    ("Draft the App Store description", 1, 10 * 60, 60, "high", ["release", "writing"], ""),
    ("Localise the date formats", 1, 14 * 60, 120, "medium", ["engineering"], ""),
    ("Record the widget walkthrough", 2, 11 * 60, 45, "medium", ["design"], ""),
    ("Fix the calendar drag threshold", 2, 15 * 60, 90, "high", ["engineering"], ""),
    ("Write the privacy answers", 3, 9 * 60 + 30, 45, "high", ["release"], ""),
    ("Interview: keyboard-first users", 3, 13 * 60, 60, "medium", ["research"], ""),
    ("Prune the notification copy", 4, 10 * 60, 30, "low", ["writing"], ""),
    ("Retrospective", 4, 16 * 60, 45, "none", ["planning"], ""),
    ("Sync the widget timeline refresh", 5, 11 * 60, 60, "medium", ["engineering"], ""),
    ("Archive last quarter's notes", 6, 15 * 60, 30, "low", ["planning"], ""),
]

MONTH_TASKS = [
    ("Submit 1.0 for review", 8, 10 * 60, 60, "high", ["release"], ""),
    ("Rework the goal progress ring", 10, 13 * 60, 90, "medium", ["design"], ""),
    ("Migration dry run on a copy of the store", 12, 9 * 60, 120, "high", ["engineering"], ""),
    ("Quarterly planning offsite", 15, 9 * 60, 240, "medium", ["planning"], ""),
    ("Refresh the support page", 18, 14 * 60, 45, "low", ["writing"], ""),
    ("1.0.1 bug bash", 22, 10 * 60, 180, "medium", ["release"], ""),
]

BACKLOG_TASKS = [
    ("Sketch a compact timeline row", "low", ["design"]),
    ("Audit every empty state for a next action", "medium", ["design"]),
    ("Decide on a keyboard shortcut for Focus", "low", ["engineering"]),
    ("Read the CloudKit conflict-resolution notes", "low", ["research"]),
]

DAILY_NOTE = """# Thursday

Shipping week. The build is green and the only thing between us and review is
the metadata.

## Decisions

- **Onboarding** copy leads with *"Plan today"* rather than a feature tour.
- Calendar stays read-only for 1.0. Two-way sync is a 1.1 problem.
- The widget ships with the small and medium sizes only.

## Open questions

- [ ] Does the timeline need a "now" line when nothing is scheduled?
- [ ] Who signs off on the privacy answers?
- [x] Settle the release-branch cut time

## Notes from design review

The planner reads well at 1440pt but the section headers crowd below 1100pt.
Worth a pass before the screenshots go out.

> The empty state is the screen people judge us on.
"""

WEEKLY_NOTE = """# Week focus

1. Ship the 1.0 build to review.
2. Close every open accessibility finding.
3. Write the release notes while the work is still fresh.

## Shipped

- Weekly planner keyboard navigation
- Widget timeline refresh on external writes
- Markdown table rendering in notes
"""

PERMANENT_NOTE = """# How I plan

A day is planned once, in the morning, and re-planned only when something
breaks. Everything that does not have a time is a decision I have not made yet.

- The list is a queue, not a promise.
- Anything older than two weeks either gets a date or gets deleted.
- Notes hold the reasoning; tasks hold only the next action.
"""


def guard_store_path(store: str) -> None:
    resolved = os.path.abspath(os.path.expanduser(store))
    for fragment in REFUSED_SUBSTRINGS:
        if fragment in resolved:
            raise SystemExit(
                f"REFUSING: {resolved} is the user's real Cadence store. "
                "Point --store at a throwaway path under $TMPDIR."
            )
    if resolved.startswith(os.path.expanduser("~/Library/Containers")):
        raise SystemExit(f"REFUSING: {resolved} is inside an app container.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", required=True, help="Path to the built CadenceMCPServer binary.")
    parser.add_argument("--store", required=True, help="Throwaway store path to seed.")
    args = parser.parse_args()

    guard_store_path(args.store)
    if not os.path.exists(args.server):
        raise SystemExit(f"No CadenceMCPServer at {args.server}. Build the CadenceMCPServer scheme first.")

    client = MCPClient(args.server, args.store)
    created = 0
    try:
        for title, offset, start, estimate, priority, tags, notes in TODAY_TASKS + WEEK_TASKS + MONTH_TASKS:
            payload = {"title": title, "scheduledDate": day(offset), "priority": priority}
            if start is not None:
                payload["scheduledStartMin"] = start
            if estimate is not None:
                payload["estimatedMinutes"] = estimate
            if tags:
                payload["tagNames"] = tags
            if notes:
                payload["notes"] = notes
            client.call("create_task", payload)
            created += 1

        for title, offset, start, estimate, priority, tags, notes in DONE_TODAY:
            payload = {"title": title, "scheduledDate": day(offset), "priority": priority}
            if start is not None:
                payload["scheduledStartMin"] = start
            if estimate is not None:
                payload["estimatedMinutes"] = estimate
            if tags:
                payload["tagNames"] = tags
            result = client.call("create_task", payload)
            created += 1
            # `create_task` answers a task envelope whose identifier lives under `summary`.
            # Reading `result["id"]` instead returns None and silently leaves the task open,
            # which is how the first seeded run produced a Today column with nothing done.
            task_id = (result or {}).get("summary", {}).get("id")
            if not task_id:
                raise RuntimeError(f"create_task gave no summary.id for {title!r}: {result!r}")
            client.call("complete_task", {"taskId": task_id})

        for title, priority, tags in BACKLOG_TASKS:
            client.call("create_task", {"title": title, "priority": priority, "tagNames": tags})
            created += 1

        client.call("append_core_note", {"kind": "daily", "content": DAILY_NOTE})
        client.call("append_core_note", {"kind": "weekly", "content": WEEKLY_NOTE})
        client.call("append_core_note", {"kind": "permanent", "content": PERMANENT_NOTE})

        summary = client.call("list_tasks", {"limit": 1})
        print(f"seeded {created} tasks; store reports totalCount={summary.get('totalCount')}")
        print("seeded daily, weekly and permanent notes")
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
