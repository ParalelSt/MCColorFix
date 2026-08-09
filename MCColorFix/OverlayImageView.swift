import Cocoa

final class OverlayImageView: NSView {
    private var currentImage: CGImage?

    override var isFlipped: Bool { true }

    func updateImage(_ image: CGImage) {
        currentImage = image
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = currentImage, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high

        // isFlipped=true gives us a top-left origin coordinate system for
        // layout, but CGContext.draw(_:in:) always draws using CG's
        // bottom-left image convention. Since the context is already
        // flipped, that combination draws the image upside down. Undo the
        // flip just for this draw call.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: bounds)
        ctx.restoreGState()
    }
}
