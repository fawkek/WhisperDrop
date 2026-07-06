import AppKit
import SwiftUI

struct GlassWindowConfigurator: NSViewRepresentable {
    private static let backgroundIdentifier = NSUserInterfaceItemIdentifier("WhisperDrop.WindowGlass")
    private static let titlebarIdentifier = NSUserInterfaceItemIdentifier("WhisperDrop.TitlebarGlass")

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

            guard let frameView = window.contentView?.superview else { return }
            if frameView.subviews.first(where: { $0.identifier == Self.backgroundIdentifier }) == nil {
                let glass = makeGlass(identifier: Self.backgroundIdentifier)
                frameView.addSubview(glass, positioned: .below, relativeTo: nil)
                pin(glass, to: frameView)
            }

            if let closeButton = window.standardWindowButton(.closeButton),
               let titlebarView = closeButton.superview,
               titlebarView.subviews.first(where: { $0.identifier == Self.titlebarIdentifier }) == nil
            {
                let titlebarGlass = makeGlass(identifier: Self.titlebarIdentifier)
                titlebarView.addSubview(titlebarGlass, positioned: .below, relativeTo: closeButton)
                pin(titlebarGlass, to: titlebarView)
            }
            frameView.needsLayout = true
            frameView.needsDisplay = true
        }
    }

    private func makeGlass(identifier: NSUserInterfaceItemIdentifier) -> NSVisualEffectView {
        let glass = NSVisualEffectView(frame: .zero)
        glass.identifier = identifier
        glass.material = .underWindowBackground
        glass.blendingMode = .behindWindow
        glass.state = .followsWindowActiveState
        glass.translatesAutoresizingMaskIntoConstraints = false
        return glass
    }

    private func pin(_ view: NSView, to container: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
