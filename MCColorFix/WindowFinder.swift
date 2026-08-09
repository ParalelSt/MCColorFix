import Cocoa
import ScreenCaptureKit

struct TargetWindow {
    let scWindow: SCWindow
    let frame: CGRect
    let title: String
}

enum WindowFinder {

    /// Finds candidate windows whose owning app name or window title contains "minecraft".
    static func findMinecraftWindows() async -> [TargetWindow] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            let matches = content.windows.filter { window in
                let appName = window.owningApplication?.applicationName.lowercased() ?? ""
                let title = window.title?.lowercased() ?? ""
                return appName.contains("minecraft") || title.contains("minecraft")
            }

            return matches.map { window in
                TargetWindow(
                    scWindow: window,
                    frame: window.frame,
                    title: window.title ?? window.owningApplication?.applicationName ?? "Minecraft"
                )
            }
        } catch {
            print("Failed to enumerate windows: \(error)")
            return []
        }
    }

    /// Re-resolves the live on-screen frame for a given window id via CoreGraphics,
    /// since SCWindow.frame is a snapshot from when we enumerated it.
    static func currentFrame(forWindowID windowID: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let dict = info.first,
              let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }
        return CGRect(
            x: boundsDict["X"] ?? 0,
            y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0,
            height: boundsDict["Height"] ?? 0
        )
    }
}
