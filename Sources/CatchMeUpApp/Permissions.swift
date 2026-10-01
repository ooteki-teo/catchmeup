import AppKit
import CoreGraphics

/// Screen-recording access (required by `screencapture` / the ⌘⇧M shortcut).
enum ScreenRecording {
    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompts the user. Should only be called from an explicit Settings action.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }
}
