# Focus Timer Continuity and Navigation

```text
Tree read: 9b31280
Dirty entries at capture: 24 (git status --short; untracked directories count as one)
Source examined: clean git archive of 9b31280; dirty work excluded
Mode: source-only audit; no app launches, builds, or tests
```

## FC-1: Mac Time Accounting Depends on a View's Timer Deliveries

**P2 / elapsed-time correctness / inferred from lifecycle and accounting code; not timed in the app.**

**Can this happen today?** Start focus on Mac, navigate to another Cadence destination, spend time there, then return or switch tasks. RootDetailContent conditionally creates FocusView only for the focus selection. The long-lived FocusManager still says the session is running, but its only elapsed-time increment belongs to that conditional view. Delayed main-run-loop delivery is another risk even while the view remains visible.

**Exact spots:**
- [FocusView.swift:15](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/FocusView.swift:15): one-second publisher is a view property.
- [FocusView.swift:30](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/FocusView.swift:30): every received event adds exactly one second; event timestamp is ignored.
- [macOSRootStateSupport.swift:10](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/macOSRootStateSupport.swift:10) and [line 30](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/macOSRootStateSupport.swift:30): switching destinations replaces the FocusView branch.
- [FocusManager.swift:14](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Services/FocusManager.swift:14): session, isRunning, and elapsed survive independently in the manager.
- [macOSRootLifecycleSupport.swift:56](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/macOSRootLifecycleSupport.swift:56): selection changes adjust sidebar visibility, not timer banking or pause state.
- [FocusManager.swift:113](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Services/FocusManager.swift:113): banking consumes the accumulated counter, not actual elapsed duration.

**Measured source inventory:** `elapsed +=` has one production match, FocusView.swift:32. **Inferred consequence:** time spent without that subscriber, or with delayed deliveries, is absent from the counter later banked into task/list totals. Exact subscription teardown and wall-clock discrepancy remain runtime verification work.

This is not the old T-654 swallowed-bank failure: that fix correctly commits before resetting. Here the amount being committed can already be wrong.

## 30-Second Confirmation

```sh
git grep -n -E 'elapsed[[:space:]]*\+=' 9b31280 -- Cadence
git show 9b31280:Cadence/macOS/Views/FocusView.swift | sed -n '6,34p'
git show 9b31280:Cadence/macOS/Views/macOSRootStateSupport.swift | sed -n '6,35p'
git show 9b31280:Cadence/macOS/Services/FocusManager.swift | sed -n '96,116p'
```

## Suggested Fix

Make the manager own a running time interval and accumulated paused duration. A view timer should only request display refreshes, never be the accounting source. Reuse the shape of [CadenceFocusTimerState.swift's actual declaration in CadenceFocusPlanningSupport.swift:4](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadenceFocusPlanningSupport.swift:4): it computes elapsed time from an injected timestamp rather than tick count.

Choose navigation and sleep policy explicitly. If leaving Focus should pause/bank, make that an explicit transition and update isRunning; if it should continue, account for the full interval without a view subscription. Do not silently change iOS's intentional onDisappear banking policy while repairing Mac ownership. Wall-clock adjustment behavior deserves a policy decision before copying Date-based arithmetic wholesale.

Keep T-654's commit-before-reset behavior: a failed bank must retain the session and its elapsed duration. Avoid adding a second ticking singleton alongside the existing view increment, which could double-count.

## Acceptance Checks, Not Run

- Advance an injected clock by 90 seconds with zero display ticks; a continuing session banks 90 seconds, subject to the existing rounding policy.
- Navigate Focus > Notes > Focus; verify the chosen continue-or-explicit-pause policy.
- Delayed redraws do not change credited duration.
- Pause, resume, switch task, switch bundle, and failed bank preserve their current accounting contracts.
- A view-level timer callback cannot increment a second counter after the refactor.

## Dedup and Test Gap

Searched focus/navigation/tick/background/disappear terms in TODO and TODO_DONE. Existing T-654 and focus-picker work concern committing and switching, not a view-owned elapsed producer.

[FocusPickerPlayControlTests.swift:26](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/FocusPickerPlayControlTests.swift:26) already advances supplied timestamps for the shared timer. Existing focus commit tests validate saved amounts and refusal handling. Those tests do not show that Mac's real clock continues while its screen is absent; no such runtime test was executed here.

## Looks Solid and Patch Order

The shared timestamp timer offers a small existing pattern. Mac startFocus/endSession refuse to clear a failed outgoing session; iOS has explicit leave-screen banking at [iOSFocusView.swift:125](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSFocusView.swift:125).

First choose navigation policy, then move accounting into FocusManager, then pin it with injected time plus one navigation-level check. No session-ledger schema change is required by this finding.

