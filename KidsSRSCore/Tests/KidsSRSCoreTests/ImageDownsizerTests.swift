import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import KidsSRSCore

final class ImageDownsizerTests: XCTestCase {

    /// An opaque RGB image of the given size, PNG-encoded (no UIKit needed).
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    func testDownsizesLongEdgeAndPreservesAspectRatio() throws {
        let big = try pngData(width: 2000, height: 1200)
        let small = try XCTUnwrap(ImageDownsizer.downsized(big, maxPixel: 800))
        let size = try pixelSize(of: small)
        XCTAssertEqual(max(size.width, size.height), 800, "long edge clamps to maxPixel")
        XCTAssertLessThanOrEqual(abs(min(size.width, size.height) - 480), 1, "aspect preserved")
    }

    func testReturnsNilForNonImageData() {
        XCTAssertNil(ImageDownsizer.downsized(Data("not an image".utf8)))
    }
}
