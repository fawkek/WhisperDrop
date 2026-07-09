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
            CommandMenu(AppText.pick("Диагностика", "Diagnostics")) {
                Button(AppText.pick("Показать лог", "Show Log"), action: store.showLog)
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button(AppText.pick("Показать папку логов", "Show Logs Folder"), action: store.showLogsFolder)
            }
        }

        Window(AppText.pick("О WhisperDrop", "About WhisperDrop"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
