import SwiftUI

@main
struct MCColorFixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar controls; the actual overlay is a separate NSWindow
        // managed by AppDelegate/OverlayController.
        MenuBarExtra("MC Color Fix", systemImage: "eye") {
            ControlPanelView()
                .environmentObject(appDelegate.overlayController)
        }
        .menuBarExtraStyle(.window)
    }
}
