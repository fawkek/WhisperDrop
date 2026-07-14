import AppKit
import SwiftUI

struct GlassWindowConfigurator: NSViewRepresentable {
    private static let backgroundIdentifier = NSUserInterfaceItemIdentifier("WhisperDrop.WindowGlass")
    private static let configuredIdentifier = NSUserInterfaceItemIdentifier("WhisperDrop.WindowConfigured")

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWhenAttached(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWhenAttached(view)
    }

    private func configureWhenAttached(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

            if view.identifier != Self.configuredIdentifier {
                window.setContentSize(NSSize(width: 600, height: 600))
                view.identifier = Self.configuredIdentifier
            }

            guard let frameView = window.contentView?.superview else { return }
            if frameView.subviews.first(where: { $0.identifier == Self.backgroundIdentifier }) == nil {
                let glass = NSVisualEffectView(frame: .zero)
                glass.identifier = Self.backgroundIdentifier
                glass.material = .sidebar
                glass.blendingMode = .behindWindow
                glass.state = .active
                glass.translatesAutoresizingMaskIntoConstraints = false
                frameView.addSubview(glass, positioned: .below, relativeTo: nil)
                NSLayoutConstraint.activate([
                    glass.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
                    glass.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),
                    glass.topAnchor.constraint(equalTo: frameView.topAnchor),
                    glass.bottomAnchor.constraint(equalTo: frameView.bottomAnchor),
                ])
            }

            frameView.needsLayout = true
            frameView.needsDisplay = true
        }
    }
}
