import SwiftUI
import ScreenCaptureKit

struct ControlPanelView: View {
    @EnvironmentObject var overlay: OverlayController
    @State private var showAllWindows = false

    /// Show the full list when the user asked for it, or automatically when
    /// the heuristics found nothing — otherwise there would be no way to
    /// select a window the scoring missed.
    private var windowsToShow: [TargetWindow] {
        let likely = overlay.likelyWindows
        if showAllWindows || likely.isEmpty { return overlay.allWindows }
        return likely
    }

    private static let rowHeight: CGFloat = 44
    private static let maxListHeight: CGFloat = 264

    /// A ScrollView reports an ideal height of 0, and MenuBarExtra sizes its
    /// window to the content's ideal height — so a maxHeight-only constraint
    /// collapses the list to nothing. Give it a definite height instead.
    private var listHeight: CGFloat {
        min(CGFloat(windowsToShow.count) * Self.rowHeight, Self.maxListHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Minecraft Color Fix")
                    .font(.headline)
                Spacer()
                // Makes it unambiguous which build is running — several copies
                // of this app tend to accumulate in Downloads.
                Text(OverlayController.versionString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(overlay.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if overlay.needsScreenRecordingPermission {
                Button("Open Screen Recording Settings") {
                    overlay.openScreenRecordingSettings()
                }
            }
            if overlay.isTranslocated {
                Button("Reveal app in Finder") {
                    overlay.revealAppInFinder()
                }
            }

            Divider()

            if !overlay.needsScreenRecordingPermission {
                if windowsToShow.isEmpty {
                    Button("Find Minecraft Window") {
                        overlay.refreshWindowList()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(windowsToShow, id: \.scWindow.windowID) { window in
                                Button {
                                    overlay.start(target: window)
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(window.displayName)
                                        Text(window.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .frame(height: Self.rowHeight)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .frame(height: listHeight)

                    HStack {
                        Button("Refresh") {
                            overlay.refreshWindowList()
                        }
                        Spacer()
                        // Hidden when the list is already showing everything.
                        if !overlay.likelyWindows.isEmpty {
                            Button(showAllWindows ? "Show likely only" : "Show all windows") {
                                showAllWindows.toggle()
                            }
                        }
                    }
                    .font(.caption)
                }
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
        .frame(width: 300)
        .onAppear {
            overlay.refreshWindowList()
        }
    }
}
