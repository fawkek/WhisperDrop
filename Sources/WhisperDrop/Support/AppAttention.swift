import AppKit

/// Lets the user know long work has finished while the window is in the background:
/// a badge on the Dock icon and one bounce. Both are visual, so they work for people
/// who wouldn't hear a sound.
@MainActor
enum AppAttention {
    static func workFinished() {
        guard let app = NSApp, !app.isActive else { return }
        app.dockTile.badgeLabel = "✓"
        app.requestUserAttention(.informationalRequest)
    }

    static func clear() {
        NSApp?.dockTile.badgeLabel = nil
    }
}
