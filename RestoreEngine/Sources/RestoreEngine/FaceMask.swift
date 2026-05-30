import Foundation

/// Turns a BiSeNet face-parsing class map into a feathered 0…1 alpha mask covering the face
/// region, used to blend the restored face onto the background so only the face is replaced
/// and its edges fade smoothly (the role facexlib's parse mask plays in paste-back).
public enum FaceMask {

    /// CelebAMask-HQ / BiSeNet classes that count as "face" (skin + features; excludes
    /// background 0, neck 14/15, cloth 16, hair 17, hat 18 so we don't paste over them).
    static let faceClasses: Set<Int32> = [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13]

    /// Build a feathered mask from a `width*height` class map.
    public static func feathered(classMap: [Int32], width: Int, height: Int, featherSigma: Double = 9) -> [Float] {
        precondition(classMap.count == width * height)
        var binary = [Float](repeating: 0, count: classMap.count)
        for i in 0..<classMap.count where faceClasses.contains(classMap[i]) { binary[i] = 1 }
        return Filters.gaussianBlur(binary, width: width, height: height, sigma: featherSigma)
    }
}
