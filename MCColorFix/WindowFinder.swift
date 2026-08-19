import Cocoa
import ScreenCaptureKit

struct TargetWindow {
    let scWindow: SCWindow
    let frame: CGRect
    let title: String
    let appName: String
    /// Heuristic confidence that this window is the Minecraft game window.
    /// See `WindowFinder.score(for:)` for how it is derived.
    let score: Int

    var isLikelyMinecraft: Bool { score >= TargetWindow.likelyThreshold }

    /// Shown in the picker. Window titles are only readable once Screen
    /// Recording is granted, so fall back to the owning app name.
    var displayName: String {
        if !title.isEmpty { return title }
        return appName
    }

    /// Secondary line in the picker, so two same-named windows stay tellable apart.
    var subtitle: String {
        let size = "\(Int(frame.width))×\(Int(frame.height))"
        if title.isEmpty || title == appName { return size }
        return "\(appName) — \(size)"
    }

    static let likelyThreshold = 60
}

/// Why a window lookup produced no usable list. Callers need to tell these
/// apart: "permission denied" and "nothing matched" require completely
/// different things from the user, and conflating them is misleading.
enum WindowLookupResult {
    case success([TargetWindow])
    case permissionDenied
    case failed(String)
}

enum WindowFinder {

    // MARK: Heuristics

    /// Bundle identifiers of JVM runtimes. Minecraft is a Java app, so the
    /// window's owning process is a JVM no matter which launcher started it.
    private static let jvmBundlePrefixes = [
        "com.azul.zulu",            // Zulu — what Prism ships by default
        "net.java.openjdk",
        "net.adoptopenjdk",
        "net.temurin",
        "org.openjdk",
        "com.oracle.java",
        "com.microsoft.openjdk",
        "com.amazon.corretto",
        "org.graalvm",
        "net.minecraft"             // official launcher's bundled runtime
    ]

    /// The owning process is literally named after a Java runtime. Strong
    /// signal on its own — real Java desktop apps (IntelliJ, etc.) ship a
    /// branded bundle rather than presenting as bare "java".
    private static let jvmNameHints = ["java", "jdk", "jre", "openjdk"]

    /// Launcher / client names that show up as the owning app name. Prism and
    /// MultiMC rename the game process to the *instance* name, so the app name
    /// is frequently something like `"Prism Launcher: b1.8.1"` with no
    /// "minecraft" anywhere in it — which is exactly why a plain substring
    /// match on "minecraft" misses the window entirely.
    ///
    /// Deliberately a *weak* signal: the launcher's own window carries the same
    /// name as the game window it spawned, so this can never qualify a window
    /// on its own.
    private static let launcherKeywords = [
        "prism", "multimc", "polymc", "atlauncher", "gdlauncher",
        "modrinth", "curseforge", "technic", "ftb", "badlion",
        "lunar", "feather", "salwyrr"
    ]

    /// Apps that routinely carry "minecraft" in a window title without being
    /// the game: a wiki tab, a chat channel, a source folder. Without this a
    /// browser window outranks the real game window in the picker.
    private static let nonGameBundlePrefixes = [
        "com.apple.safari", "com.google.chrome", "org.mozilla", "com.microsoft.edge",
        "com.brave.browser", "company.thebrowser", "com.operasoftware",
        "com.hnc.discord", "com.tinyspeck", "com.microsoft.teams",
        "com.microsoft.vscode", "com.apple.dt.xcode", "com.jetbrains",
        "com.apple.terminal", "com.googlecode.iterm2", "dev.warp",
        "com.apple.finder", "md.obsidian", "notion.id"
    ]

    /// Minecraft's default window is 854×480 of content. Launchers usually keep
    /// that default, and the framed window comes out a little taller.
    private static func hasClassicMinecraftSize(_ frame: CGRect) -> Bool {
        let w = frame.width, h = frame.height
        guard w >= 640, h >= 480 else { return false }
        // 854 wide is the giveaway; height varies with the title bar.
        if abs(w - 854) < 2 && h >= 480 && h <= 560 { return true }
        // 16:9-ish, but only at a plausible *windowed* game size — without the
        // width bound this matches every maximized window on the display.
        let ratio = w / h
        return w <= 1600 && ratio > 1.6 && ratio < 1.85
    }

    private static func score(for window: SCWindow) -> Int {
        score(
            appName: window.owningApplication?.applicationName ?? "",
            title: window.title ?? "",
            bundleID: window.owningApplication?.bundleIdentifier ?? "",
            frame: window.frame,
            isOnScreen: window.isOnScreen
        )
    }

    /// Value-based so it can be exercised directly; `SCWindow` cannot be
    /// constructed outside of ScreenCaptureKit.
    static func score(
        appName rawAppName: String,
        title rawTitle: String,
        bundleID rawBundleID: String,
        frame: CGRect,
        isOnScreen: Bool
    ) -> Int {
        let appName = rawAppName.lowercased()
        let title = rawTitle.lowercased()
        let bundleID = rawBundleID.lowercased()
        var score = 0

        // --- Strong signals: any one of these alone clears `likelyThreshold`.
        // The game names its own window "Minecraft <version>", but the title is
        // only readable once Screen Recording is granted.
        if title.contains("minecraft") { score += 100 }
        if appName.contains("minecraft") { score += 80 }
        // Minecraft is a Java app, so its window is always owned by a JVM
        // process no matter which launcher started it. This is what catches
        // Prism/MultiMC instances renamed to something with no "minecraft" in it.
        if jvmBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) {
            score += 60
        } else {
            // Whole-word match: a substring test would fire on unrelated names
            // that merely contain "jre" or "jdk".
            let words = Set(appName.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            if !words.isDisjoint(with: jvmNameHints) { score += 60 }
        }

        // Strong negative: these apps show "minecraft" in titles constantly and
        // are never the game.
        if nonGameBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) { score -= 150 }

        // --- Weak signals: ranking nudges only, never enough to qualify a
        // window by themselves. Any 16:9 window would otherwise look like a
        // game, and every launcher's own window shares the launcher's name.
        if launcherKeywords.contains(where: { appName.contains($0) || title.contains($0) }) { score += 15 }
        if hasClassicMinecraftSize(frame) { score += 15 }
        if isOnScreen { score += 5 }

        return score
    }

    /// Windows we should never offer: our own overlay, menu bars, tiny
    /// utility panels and other chrome.
    private static func isPlausibleTarget(_ window: SCWindow) -> Bool {
        guard window.windowLayer == 0 else { return false }
        guard window.frame.width >= 200, window.frame.height >= 150 else { return false }
        let bundleID = window.owningApplication?.bundleIdentifier ?? ""
        return bundleID != Bundle.main.bundleIdentifier
    }

    // MARK: Lookup

    /// Enumerates every capturable window, scored and sorted so the most
    /// likely Minecraft window comes first.
    ///
    /// Off-screen windows are included on purpose: a window living on another
    /// Space is not "on screen", and excluding those is a common reason a
    /// running game appears undetectable.
    static func findWindows() async -> WindowLookupResult {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )

            let candidates = content.windows
                .filter(isPlausibleTarget)
                .map { window in
                    TargetWindow(
                        scWindow: window,
                        frame: window.frame,
                        title: window.title ?? "",
                        appName: window.owningApplication?.applicationName ?? "Unknown app",
                        score: score(for: window)
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }

            return .success(candidates)
        } catch let error as SCStreamError where error.code == .userDeclined {
            return .permissionDenied
        } catch {
            // -3801 is also surfaced without being bridged to SCStreamError
            // on some macOS versions, so check the raw code too.
            let nsError = error as NSError
            if nsError.domain.contains("ScreenCaptureKit"), nsError.code == -3801 {
                return .permissionDenied
            }
            return .failed(error.localizedDescription)
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
