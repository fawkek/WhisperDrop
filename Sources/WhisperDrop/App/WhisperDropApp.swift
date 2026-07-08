import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct WhisperDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("WhisperDrop", id: "main") {
            ContentView(store: store)
        }
        .windowResizability(.contentSize)
        .commands {
            AboutCommands()
            CommandGroup(replacing: .newItem) {
                Button(AppText.pick("Открыть файл…", "Open File…"), action: store.chooseFile)
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(store.isWorking)
            }
        }

        Window(AppText.pick("О WhisperDrop", "About WhisperDrop"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
