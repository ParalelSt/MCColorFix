import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies a pure red/blue channel swap to a CIImage.
/// This is an exact swap (R<->B), not a hue rotation or approximation.
enum ColorSwapRenderer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func swapRedBlue(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        // CIColorMatrix vectors are (R, G, B, A) weights per output channel.
        // Output.R = input.B, Output.B = input.R, G and A pass through.
        filter.rVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        filter.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        filter.bVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filter.outputImage ?? image
    }

    static func renderToCGImage(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }
}
