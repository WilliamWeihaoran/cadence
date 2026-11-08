-- Dump window <win> of process <pid>: index, role, AXIdentifier, description, value, frame, actions.
-- Usage: osascript dump.applescript <pid> <win>   (T-13542; see Cadence/macOS/AGENTS.md)
on run argv
  set thePid to (item 1 of argv) as integer
  set winIdx to (item 2 of argv) as integer
  set out to {}
  tell application "System Events"
    tell (first process whose unix id is thePid)
      set end of out to "WINDOWS=" & ((count of windows) as text)
      tell window winIdx
        set els to entire contents
        set i to 0
        repeat with e in els
          set i to i + 1
          try
            set r to role of e
            set idf to ""
            try
              set idf to (value of attribute "AXIdentifier" of e) as text
            end try
            set ad to ""
            try
              set ad to (value of attribute "AXAttributedDescription" of e) as text
            end try
            if ad is "" then
              try
                set ad to (description of e) as text
              end try
            end if
            set v to ""
            try
              set v to (value of e) as text
            end try
            set p to position of e
            set s to size of e
            set acts to ""
            try
              set acts to (name of actions of e) as text
            end try
            set end of out to ((i as text) & " " & r & " | id=" & idf & " | d=" & ad & " | v=" & v & " | " & ((item 1 of p) as text) & "," & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & "x" & ((item 2 of s) as text) & " | " & acts)
          end try
        end repeat
      end tell
    end tell
  end tell
  set AppleScript's text item delimiters to linefeed
  return out as text
end run
