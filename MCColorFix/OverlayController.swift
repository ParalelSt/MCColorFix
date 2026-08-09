import Cocoa
import ScreenCaptureKit
import CoreImage
internal import Combine

@MainActor
final class OverlayController: NSObject, ObservableObject {

    @Published var isRunning = false
    @Published var statusText = "Not running"
    @Published var availableWindows: [TargetWindow] = []

    private var stream: SCStream?
    private var streamOutput: CaptureOutput?
    private var overlayWindow: NSWindow?
    private var overlayView: OverlayImageView?
    private var trackingTimer: Timer?
    private var targetWindowID: CGWindowID?

    // MARK: Permissions

    func requestScreenRecordingPermissionIfNeeded() {
        Task {
            do {
                // Triggers the system permission prompt if not already granted.
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                statusText = "Screen Recording permission needed. Enable it in System Settings > Privacy & Security > Screen Recording, then relaunch."
            }
        }
    }

    // MARK: Discovery

    func refreshWindowList() {
        Task {
            let windows = await WindowFinder.findMinecraftWindows()
            self.availableWindows = windows
            if windows.isEmpty {
                statusText = "No Minecraft window found. Make sure Minecraft is running in windowed mode."
            } else {
                statusText = "Found \(windows.count) window(s). Select one to start."
            }
        }
    }

    // MARK: Start / stop

    func start(target: TargetWindow) {
        Task {
            do {
                try await startCapture(target: target)
                isRunning = true
                statusText = "Running — overlay active on \(target.title)"
                startWindowTracking(windowID: target.scWindow.windowID)
            } catch {
                statusText = "Failed to start: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        Task {
            try? await stream?.stopCapture()
            stream = nil
            streamOutput = nil
        }
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
