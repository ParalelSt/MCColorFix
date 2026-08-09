import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    let overlayController = OverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app, no dock icon.
        NSApp.setActivationPolicy(.accessory)
        overlayController.requestScreenRecordingPermissionIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlayController.stop()
    }
}
