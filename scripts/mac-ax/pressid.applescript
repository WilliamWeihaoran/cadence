-- Perform a NAMED action (e.g. AXPress) on the nth element whose AXIdentifier matches.
-- Usage: osascript pressid.applescript <pid> <win> <identifier> <action> [nth]   (T-13542)
on run argv
  set thePid to (item 1 of argv) as integer
  set winIdx to (item 2 of argv) as integer
  set wantId to item 3 of argv
  set actName to item 4 of argv
  set nth to 1
  if (count of argv) > 4 then set nth to (item 5 of argv) as integer
  set hits to 0
  tell application "System Events"
    tell (first process whose unix id is thePid)
      tell window winIdx
        set els to entire contents
        repeat with e in els
          try
            set idf to (value of attribute "AXIdentifier" of e) as text
            if idf is wantId then
              set hits to hits + 1
              if hits is nth then
                perform action actName of e
                return "PRESSED " & wantId & " #" & nth
              end if
            end if
          end try
        end repeat
      end tell
    end tell
  end tell
  return "NOT FOUND id=" & wantId & " (hits=" & hits & ")"
end run
