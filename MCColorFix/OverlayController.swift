import Cocoa
import ScreenCaptureKit
import CoreImage
internal import Combine

@MainActor
final class OverlayController: NSObject, ObservableObject {

    @Published var isRunning = false
    @Published var statusText = "Not running"
    /// Every capturable window, best guess first.
    @Published var allWindows: [TargetWindow] = []
    /// True when the last lookup failed because Screen Recording is not granted.
    @Published var needsScreenRecordingPermission = false
    /// True when the app is running from a translocated (randomized) path,
    /// which makes granting Screen Recording permission impossible.
    @Published var isTranslocated = OverlayController.isTranslocated

    /// Windows the heuristics think are the game. Empty is a meaningful state:
    /// it means "we saw windows but none looked like Minecraft", which is when
    /// the UI should offer the full list instead.
    var likelyWindows: [TargetWindow] { allWindows.filter(\.isLikelyMinecraft) }

    private var stream: SCStream?
    private var streamOutput: CaptureOutput?
    private var overlayWindow: NSWindow?
    private var overlayView: OverlayImageView?
    private var trackingTimer: Timer?
    private var targetWindowID: CGWindowID?
    // MARK: Permissions

    /// Short version string shown in the UI, so it is always obvious which
    /// build is actually running.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(short) (\(build))"
    }

    /// macOS runs quarantined, unsigned apps from a randomized read-only path
    /// ("app translocation"). Because that path changes on every launch, TCC
    /// can never persist a Screen Recording grant for it — the app silently
    /// stays blind to every window, and the permission prompt may never appear
    /// at all. Moving the app out of Downloads in Finder clears the quarantine
    /// flag and stops translocation.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    func requestScreenRecordingPermissionIfNeeded() {
        // CGPreflightScreenCaptureAccess reports the current grant without
        // prompting; CGRequestScreenCaptureAccess raises the system prompt
        // explicitly. Relying on SCShareableContent to prompt implicitly is
        // unreliable for a menu-bar-only (.accessory) app, which is how this
        // app can end up permanently unable to see windows having never shown
        // the user a prompt to accept.
        isTranslocated = Self.isTranslocated

        // Translocation is reported as a warning rather than a hard stop:
        // if capture happens to work anyway, the app stays fully usable.
        guard !CGPreflightScreenCaptureAccess() else {
            needsScreenRecordingPermission = false
            return
        }

        needsScreenRecordingPermission = true
        statusText = isTranslocated ? Self.translocationMessage : Self.permissionMessage
        // Returns false when the prompt was already answered (or dismissed) in
        // a previous run; macOS only ever shows it once per app.
        _ = CGRequestScreenCaptureAccess()
    }

    /// Opens Finder at the real app bundle so the user can drag it out of
    /// Downloads, which is what stops translocation.
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    static let translocationMessage = """
        This app is running from a temporary randomized location, so macOS \
        cannot remember Screen Recording permission for it. Quit the app, move \
        MCColorFix.app to your Applications folder in Finder, then open it from \
        there.
        """

    private static let permissionMessage = """
        Screen Recording permission is required. Enable MCColorFix in System \
        Settings > Privacy & Security > Screen Recording, then quit and reopen \
        this app — macOS only applies the change after a relaunch.
        """

    // MARK: Discovery

    func refreshWindowList() {
        Task {
            switch await WindowFinder.findWindows() {
            case .permissionDenied:
                needsScreenRecordingPermission = true
                allWindows = []
                statusText = Self.isTranslocated ? Self.translocationMessage : Self.permissionMessage

            case .failed(let message):
                needsScreenRecordingPermission = false
                allWindows = []
                statusText = "Could not list windows: \(message)"

            case .success(let windows):
                needsScreenRecordingPermission = false
                allWindows = windows
                let likely = windows.filter(\.isLikelyMinecraft)
                if !likely.isEmpty {
                    statusText = "Found \(likely.count) likely Minecraft window(s)."
                } else if windows.isEmpty {
                    statusText = "No capturable windows found."
                } else {
                    statusText = """
                        No window looked like Minecraft. Pick it manually from \
                        the full list below.
                        """
                }
            }
        }
    }

    // MARK: Start / stop

    func start(target: TargetWindow) {
        Task {
            // Without this, picking a second window orphans the previous
            // overlay (an ordered-in .floating window nothing holds a
            // reference to any more) and leaves its stream writing that
            // window's frames into the new overlay's view.
            if stream != nil || overlayWindow != nil { stop() }
            do {
                try await startCapture(target: target)
                isRunning = true
                statusText = "Running — overlay active on \(target.displayName)"
                startWindowTracking(windowID: target.scWindow.windowID)
            } catch {
                statusText = "Failed to start: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        // Detach the stream *before* suspending. Awaiting first would let a
        // start() that happens during the suspension have its new stream
        // nulled out by this teardown.
        let outgoingStream = stream
        stream = nil
        streamOutput = nil
        Task { try? await outgoingStream?.stopCapture() }
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayView = nil
        isRunning = false
        statusText = "Stopped"
    }

    // MARK: Capture setup

    private func startCapture(target: TargetWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: target.scWindow)

        let config = SCStreamConfiguration()
        config.width = Int(target.frame.width * 2) // account for Retina scale; harmless if too large
        config.height = Int(target.frame.height * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // cap ~60fps
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        let output = CaptureOutput { [weak self] cgImage in
            Task { @MainActor in
                self?.overlayView?.updateImage(cgImage)
            }
        }
        try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "capture.queue"))
        try await newStream.startCapture()

        self.stream = newStream
        self.streamOutput = output
        self.targetWindowID = target.scWindow.windowID

        setupOverlayWindow(initialFrame: target.frame)
    }

    private func setupOverlayWindow(initialFrame: CGRect) {
        let view = OverlayImageView(frame: NSRect(origin: .zero, size: initialFrame.size))
        self.overlayView = view

        let window = NSWindow(
            contentRect: convertToAppKitFrame(initialFrame),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        // Deliberately NOT .canJoinAllSpaces: the overlay should live on
        // whatever Space Minecraft's window is actually on, and disappear
        // from view when you switch away, same as a normal window would.
        window.ignoresMouseEvents = true
        window.contentView = view
        // orderFrontRegardless (not makeKeyAndOrderFront / activate) shows
        // the window without taking key status or activating our app, so
        // Minecraft keeps focus and keeps receiving keyboard input.
        window.orderFrontRegardless()

        self.overlayWindow = window
    }

    // MARK: Window tracking (follow Minecraft if moved/resized)

    private func startWindowTracking(windowID: CGWindowID) {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let liveFrame = WindowFinder.currentFrame(forWindowID: windowID) else {
                    self.statusText = "Target window closed."
                    self.stop()
                    return
                }
                self.overlayWindow?.setFrame(self.convertToAppKitFrame(liveFrame), display: true)
            }
        }
    }

    /// CGWindowListCopyWindowInfo bounds are in top-left-origin screen space;
    /// AppKit windows use bottom-left-origin. Convert using the main screen height.
    private func convertToAppKitFrame(_ cgFrame: CGRect) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: cgFrame.size)
        }
        let screenHeight = screen.frame.height
        let flippedY = screenHeight - cgFrame.origin.y - cgFrame.height
        return NSRect(x: cgFrame.origin.x, y: flippedY, width: cgFrame.width, height: cgFrame.height)
    }
}

/// SCStreamOutput bridge: receives sample buffers, applies the color swap,
/// and hands back a CGImage on the main actor.
private final class CaptureOutput: NSObject, SCStreamOutput {
    let onFrame: (CGImage) -> Void
    private let ciContext = CIContext()

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let swapped = ColorSwapRenderer.swapRedBlue(ciImage)
        guard let cgImage = ColorSwapRenderer.renderToCGImage(swapped) else { return }
        onFrame(cgImage)
    }
}
