#if os(macOS)
import AppKit

func clearAppEditingFocus() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}
#endif
