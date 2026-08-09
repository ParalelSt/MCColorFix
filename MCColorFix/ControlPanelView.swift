import SwiftUI
import ScreenCaptureKit

struct ControlPanelView: View {
    @EnvironmentObject var overlay: OverlayController
    @State private var selected: TargetWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Minecraft Color Fix")
                .font(.headline)

            Text(overlay.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            if overlay.availableWindows.isEmpty {
                Button("Find Minecraft Window") {
                    overlay.refreshWindowList()
                }
            } else {
                ForEach(overlay.availableWindows, id: \.scWindow.windowID) { window in
                    Button(window.title) {
                        overlay.start(target: window)
                    }
                }
                Button("Refresh") {
                    overlay.refreshWindowList()
                }
                .font(.caption)
            }

            if overlay.isRunning {
                Divider()
                Button("Stop Overlay", role: .destructive) {
                    overlay.stop()
                }
            }

            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            overlay.refreshWindowList()
        }
    }
}
