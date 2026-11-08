-- Send keys WITHOUT activating the app (activating dismisses an open popover).
-- Usage: osascript keysnf.applescript text <string> | code <keycode> [cmd|shift] | combo <key> [cmd|cmdshift]   (T-13542)
on run argv
  set theMode to item 1 of argv
  set payload to item 2 of argv
  set mods to ""
  if (count of argv) > 2 then set mods to item 3 of argv
  tell application "System Events"
    if theMode is "text" then
      keystroke payload
    else if theMode is "code" then
      set kc to payload as integer
      if mods is "cmd" then
        key code kc using command down
      else if mods is "shift" then
        key code kc using shift down
      else
        key code kc
      end if
    else if theMode is "combo" then
      if mods is "cmd" then
        keystroke payload using command down
      else if mods is "cmdshift" then
        keystroke payload using {command down, shift down}
      else
        keystroke payload
      end if
    end if
  end tell
  return "OK"
end run
