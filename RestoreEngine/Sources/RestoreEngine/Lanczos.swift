import CoreImage
import CoreGraphics
import Foundation

/// High-quality resampling to an exact target size via Core Image's Lanczos filter.
/// Replaces the Python pipeline's PIL `Image.Resampling.LANCZOS`; the kernel differs
/// slightly from PIL's, so output parity is validated by SSIM rather than exact pixels.
public enum Lanczos {

    // A reusable GPU-backed context. Cheap to keep around; expensive to recreate per call.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    public static func resize(_ image: RGBImage, toWidth tw: Int, toHeight th: Int) -> RGBImage {
        if tw == image.width && th == image.height { return image }
        guard tw > 0, th > 0, let cg = image.makeCGImage() else { return image }

        // Clamp to extent so the Lanczos kernel's negative lobes sample repeated edge
        // pixels at the border instead of transparent black (which darkens edges).
        let ci = CIImage(cgImage: cg).clampedToExtent()
        let scaleY = Double(th) / Double(image.height)
        let scaleX = Double(tw) / Double(image.width)

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return image }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(scaleY, forKey: kCIInputScaleKey)
        filter.setValue(scaleX / scaleY, forKey: "inputAspectRatio")

        guard let output = filter.outputImage else { return image }
        let rect = CGRect(x: 0, y: 0, width: tw, height: th)
        guard let outCG = context.createCGImage(output, from: rect) else { return image }
        return RGBImage(cgImage: outCG)
    }
}
