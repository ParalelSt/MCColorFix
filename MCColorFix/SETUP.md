# MC Color Fix — Setup Guide

A menu-bar macOS app that captures a Minecraft window and displays a red/blue
channel-swapped overlay on top of it, positioned and sized to match.

## 1. Create the Xcode project

1. Open Xcode → **File → New → Project**
2. Choose **macOS → App**
3. Product Name: `MCColorFix`
4. Interface: **SwiftUI**
5. Language: **Swift**
6. Uncheck "Use Core Data" / "Include Tests" (not needed)
7. Save it anywhere you like

## 2. Replace the generated files

Delete the default `ContentView.swift` and the app file Xcode generated, then
drag all `.swift` files from this folder into the Xcode project navigator
(check "Copy items if needed"):

- `MCColorFixApp.swift`
- `AppDelegate.swift`
- `WindowFinder.swift`
- `ColorSwapRenderer.swift`
- `OverlayController.swift`
- `OverlayImageView.swift`
- `ControlPanelView.swift`

## 3. Add required capabilities & Info.plist keys

**Screen Recording usage description:**
Select your target → **Info** tab → add a new row:
- Key: `NSScreenCaptureUsageDescription` (or "Privacy - Screen Recording Usage Description")
- Value: `This app needs to capture the Minecraft window to display it with corrected colors.`

**App Sandbox:**
This app uses ScreenCaptureKit and reads window info system-wide, which does
not play well with the App Sandbox. Go to target → **Signing & Capabilities**
and, if "App Sandbox" is present, remove it (click the `x`). This app is for
your own local use, not App Store distribution, so this is fine.

**Deployment target:**
Set minimum deployment target to **macOS 13.0** (ScreenCaptureKit requires it;
window-level capture APIs used here work best on 14.0+, so 14.0 is safer if
you're not sure which OS you're on).

## 4. Build and run

1. Launch Minecraft in **windowed mode** (not fullscreen)
2. Build and run MCColorFix (⌘R)
3. macOS will prompt for **Screen Recording permission** the first time —
   grant it in System Settings → Privacy & Security → Screen Recording, then
   relaunch the app (macOS requires a relaunch after granting this permission)
4. Click the eye icon in the menu bar
5. Pick your game window from the list. Windows are ranked with the most
   likely Minecraft window first; each row shows the owning app and pixel
   size so similarly-named windows stay distinguishable. If your window
   isn't in the list, click **Show all windows** and pick it manually.
6. A color-corrected overlay window will appear directly on top of Minecraft,
   tracking its position/size automatically

The overlay hides itself whenever Minecraft is not the frontmost app, and
comes back when you switch to it, so it does not cover your other windows.

Click "Stop Overlay" from the menu bar to remove it and interact with
Minecraft normally again.

## Troubleshooting

### "No Minecraft window found" / the window list is empty

Almost always a Screen Recording permission problem rather than an actual
missing window. The app tells the two apart and will say which it is.

**If it says the app is in a temporary randomized location:** macOS applies
"app translocation" to quarantined, unsigned apps opened from Downloads,
running them from a path that changes on every launch. Permission can never
persist for such a path, and the prompt may never appear at all. Quit the
app, move `MCColorFix.app` into `/Applications` **in Finder** (that is what
clears the quarantine flag), and open it from there.

**If it asks for Screen Recording permission:** grant it, then quit and
reopen the app — macOS only applies the change after a relaunch.

Because release builds are ad-hoc signed, macOS identifies them by code
hash rather than a stable developer identity. Every new build therefore
counts as a different app and needs permission granted again, even though
the old entry still shows as enabled in System Settings. Toggling the entry
off and on, or removing it with `-` and re-granting, fixes it.

### My launcher's window isn't detected

Click **Show all windows** and pick it manually. Scoring only ranks the
list, it never removes anything from it, so a window the heuristic scores
badly is still selectable.

Windows that are not plausible capture targets at all are excluded before
ranking: those on a non-zero window level (menus, panels, floating chrome)
and anything smaller than 200x150.

## Known limitations

- There will be a small amount of latency (roughly one frame, more under
  heavy load) between the real game and what you see in the overlay, since
  it's a capture-and-recomposite pipeline, not a direct render hook.
- If Minecraft is fullscreen rather than windowed, window tracking won't
  work — keep it windowed.
- Retina scaling: the capture config requests 2x the window's point size to
  stay sharp on Retina displays; on a non-Retina external display you can
  lower this in `OverlayController.startCapture` if it looks oversized.
- This does **not** click through to Minecraft — you're interacting directly
  with the overlay window itself, which is intentional and avoids any of the
  fragile always-on-top-transparent-passthrough tricks.
- The overlay tracks which *app* is frontmost, not which window. If Minecraft
  is frontmost, the overlay shows; it does not additionally detect the game
  window being covered by another window of the same app.
