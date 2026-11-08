-- Perform a NAMED action on element #<idx> of a dump of the same window.
-- Usage: osascript pressidx.applescript <pid> <win> <idx> <action>   (T-13542)
on run argv
  set thePid to (item 1 of argv) as integer
  set winIdx to (item 2 of argv) as integer
  set target to (item 3 of argv) as integer
  set actName to item 4 of argv
  tell application "System Events"
    tell (first process whose unix id is thePid)
      tell window winIdx
        set els to entire contents
        set e to item target of els
        perform action actName of e
        return "PRESSED #" & target & " " & (role of e as text)
      end tell
    end tell
  end tell
end run
