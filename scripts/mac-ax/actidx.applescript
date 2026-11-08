-- Perform action NUMBER <n> on element #<idx>. SwiftUI custom actions refuse by name (-1728).
-- Usage: osascript actidx.applescript <pid> <win> <idx> <n>   (T-13542)
on run argv
  set thePid to (item 1 of argv) as integer
  set winIdx to (item 2 of argv) as integer
  set target to (item 3 of argv) as integer
  set actIdx to (item 4 of argv) as integer
  tell application "System Events"
    tell (first process whose unix id is thePid)
      tell window winIdx
        set els to entire contents
        set e to item target of els
        perform action actIdx of e
        return "PERFORMED action " & actIdx & " on #" & target
      end tell
    end tell
  end tell
end run
