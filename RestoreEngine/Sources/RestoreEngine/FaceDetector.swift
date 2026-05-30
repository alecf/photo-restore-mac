import CoreGraphics
import Foundation
import Vision

/// A face found in the source image, with the 5 alignment points (image pixels, top-left
/// origin), its source-pixel size (for the restore-size gate), and the transform that warps
/// it onto the 512 template.
public struct DetectedFace: Sendable {
    public let landmarks5: [CGPoint]      // image-left-eye, image-right-eye, nose, left-mouth, right-mouth
    public let boundingBoxPx: CGRect
    public let alignTransform: Affine2x3  // source → 512 template

    /// Largest bounding-box side in source pixels (matches facexlib's size gate metric).
    public var sizePx: Int { Int(max(boundingBoxPx.width, boundingBoxPx.height).rounded()) }
}

public enum FaceDetector {

    /// Detect faces via Apple Vision and compute each one's alignment to the 512 template.
    /// Faces whose 5 points can't be derived are skipped.
    public static func detect(in image: RGBImage) throws -> [DetectedFace] {
        guard let cg = image.makeCGImage() else { return [] }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        try handler.perform([request])

        let w = image.width, h = image.height
        var faces: [DetectedFace] = []
        for obs in request.results ?? [] {
            guard let lm = obs.landmarks, let pts = fivePoints(lm, imageW: w, imageH: h) else { continue }
            let bb = obs.boundingBox  // normalized, bottom-left origin
            let rect = CGRect(
                x: bb.minX * Double(w),
                y: (1 - bb.maxY) * Double(h),
                width: bb.width * Double(w),
                height: bb.height * Double(h)
            )
            let transform = FaceAligner.similarity(from: pts, to: FaceAligner.template512)
            faces.append(DetectedFace(landmarks5: pts, boundingBoxPx: rect, alignTransform: transform))
        }
        return faces
    }

    /// Derive the 5 template points from Vision landmarks. Eyes and mouth corners are assigned
    /// by image x-position (not Vision's subject-relative "left/right" labels) so the ordering
    /// matches facexlib's image-left-first template regardless of Vision's convention.
    private static func fivePoints(_ lm: VNFaceLandmarks2D, imageW w: Int, imageH h: Int) -> [CGPoint]? {
        let size = CGSize(width: w, height: h)
        func inImage(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint]? {
            guard let region else { return nil }
            // pointsInImage uses a bottom-left origin; flip y to top-left.
            return region.pointsInImage(imageSize: size).map { CGPoint(x: Double($0.x), y: Double(h) - Double($0.y)) }
        }
        func centroid(_ pts: [CGPoint]?) -> CGPoint? {
            guard let pts, !pts.isEmpty else { return nil }
            let sx = pts.reduce(0.0) { $0 + Double($1.x) }
            let sy = pts.reduce(0.0) { $0 + Double($1.y) }
            return CGPoint(x: sx / Double(pts.count), y: sy / Double(pts.count))
        }

        let eyeA = inImage(lm.leftPupil)?.first ?? centroid(inImage(lm.leftEye))
        let eyeB = inImage(lm.rightPupil)?.first ?? centroid(inImage(lm.rightEye))
        let nose = centroid(inImage(lm.nose))
        let lips = inImage(lm.outerLips) ?? inImage(lm.innerLips)

        guard let e1 = eyeA, let e2 = eyeB, let noseP = nose, let lips, !lips.isEmpty else { return nil }
        let leftEye = e1.x <= e2.x ? e1 : e2
        let rightEye = e1.x <= e2.x ? e2 : e1
        let leftMouth = lips.min(by: { $0.x < $1.x })!
        let rightMouth = lips.max(by: { $0.x < $1.x })!
        return [leftEye, rightEye, noseP, leftMouth, rightMouth]
    }
}
