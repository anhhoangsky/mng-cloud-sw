import CoreGraphics
import XCTest
@testable import MNGEdit

/// The CPU reference of the face warp. The tests pin the two promises the
/// Metal kernel has to keep: a neutral slider is a bit-for-bit identity and a
/// pixel outside every face ellipse is never resampled.
final class FaceWarpTests: XCTestCase {
    private let face = EditorFaceAnchor(
        box: EditorFaceBox(x: 0.35, y: 0.25, width: 0.3, height: 0.4, confidence: 0.9)
    )

    /// Centre 0.5/0.5, half-size (0.15, 0.2) for the box above.
    private let centre = SIMD2<Float>(0.5, 0.5)

    func testZeroParametersAreBitwiseIdentity() {
        let warp = FaceWarp(parameters: .zero, anchors: [face])
        XCTAssertTrue(warp.isIdentity)
        for y in stride(from: Float(0), through: 1, by: 0.125) {
            for x in stride(from: Float(0), through: 1, by: 0.125) {
                let point = SIMD2<Float>(x, y)
                XCTAssertEqual(warp.warp(point), point)
            }
        }
    }

    func testNoFaceSkipsTheSliders() {
        let params = FaceWarpParameters(faceSlim: 80, eyeSize: 60)
        let warp = FaceWarp(parameters: params, anchors: [])
        XCTAssertTrue(warp.isIdentity)
        XCTAssertEqual(warp.warp(SIMD2<Float>(0.25, 0.25)), SIMD2<Float>(0.25, 0.25))
    }

    func testOutsideTheFaceEllipseIsUntouched() {
        let warp = FaceWarp(parameters: FaceWarpParameters(faceSlim: 100), anchors: [face])
        let outside = SIMD2<Float>(0.05, 0.05)
        XCTAssertEqual(warp.warp(outside), outside)
    }

    func testFaceSlimPushesTheCheekSampleOutwards() {
        let warp = FaceWarp(parameters: FaceWarpParameters(faceSlim: 50), anchors: [face])
        // local.x = 0.5, local.y = 0: the strongest cheek band.
        let point = SIMD2<Float>(centre.x + 0.075, centre.y)
        let warped = warp.warp(point)
        XCTAssertGreaterThan(warped.x, point.x)
        XCTAssertEqual(warped.y, point.y)
    }

    func testNegativeFaceSlimPushesInwards() {
        let warp = FaceWarp(parameters: FaceWarpParameters(faceSlim: -50), anchors: [face])
        let point = SIMD2<Float>(centre.x + 0.075, centre.y)
        let warped = warp.warp(point)
        XCTAssertLessThan(warped.x, point.x)
    }

    func testChinMovesTheLowerCentreOnly() {
        let warp = FaceWarp(parameters: FaceWarpParameters(chin: 70), anchors: [face])
        // local.y = 0.4: inside the chin band.
        let lower = SIMD2<Float>(centre.x, centre.y + 0.08)
        let moved = warp.warp(lower)
        XCTAssertLessThan(moved.y, lower.y)
        XCTAssertEqual(moved.x, lower.x)
        // local.y = -0.4: above the band, so the sample is untouched.
        let upper = SIMD2<Float>(centre.x, centre.y - 0.08)
        XCTAssertEqual(warp.warp(upper), upper)
    }

    func testEyeSizeOnlyAffectsTheEyeEllipse() {
        let warp = FaceWarp(parameters: FaceWarpParameters(eyeSize: 50), anchors: [face])
        // A point just outside the default left eye (local -0.30, -0.18).
        let nearEye = SIMD2<Float>(centre.x - 0.30 * 0.15, centre.y - 0.18 * 0.2)
        let warped = warp.warp(nearEye)
        XCTAssertNotEqual(warped, nearEye)
        // Positive eye size samples closer to the eye centre, enlarging it.
        XCTAssertLessThan(warped.x, nearEye.x)
        // The opposite corner of the face is outside the eye radius.
        let cheek = SIMD2<Float>(centre.x + 0.075, centre.y + 0.08)
        XCTAssertEqual(warp.warp(cheek), cheek)
    }

    func testOutputStaysInsideTheImage() {
        let params = FaceWarpParameters(
            faceSlim: 100,
            jawline: 100,
            chin: 100,
            eyeSize: 100,
            noseSize: 100,
            mouthSize: 100
        )
        let warp = FaceWarp(parameters: params, anchors: [face])
        for y in stride(from: Float(0), through: 1, by: 0.05) {
            for x in stride(from: Float(0), through: 1, by: 0.05) {
                let warped = warp.warp(SIMD2<Float>(x, y))
                XCTAssertGreaterThanOrEqual(warped.x, 0)
                XCTAssertLessThanOrEqual(warped.x, 1)
                XCTAssertGreaterThanOrEqual(warped.y, 0)
                XCTAssertLessThanOrEqual(warped.y, 1)
                XCTAssertTrue(warped.x.isFinite)
                XCTAssertTrue(warped.y.isFinite)
            }
        }
    }

    func testFacesAreSortedByConfidenceAndCappedAtFour() {
        let anchors = (0..<6).map { index in
            EditorFaceAnchor(
                box: EditorFaceBox(
                    x: 0.1,
                    y: 0.1,
                    width: 0.2,
                    height: 0.2,
                    confidence: Float(index) / 10
                )
            )
        }
        let warp = FaceWarp(parameters: FaceWarpParameters(faceSlim: 20), anchors: anchors)
        XCTAssertEqual(warp.anchors.count, 4)
        XCTAssertEqual(warp.anchors.first?.box.confidence, 0.5)
    }

    func testSlidersAreClampedAndNaNBecomesZero() {
        let params = FaceWarpParameters(faceSlim: 500, chin: -900, eyeSize: .nan).clamped()
        XCTAssertEqual(params.faceSlim, 100)
        XCTAssertEqual(params.chin, -100)
        XCTAssertEqual(params.eyeSize, 0)
    }

    /// The portrait fixture lives next to the tests and is the same photo the
    /// web harness uses, so a reshape can be compared across the two clients.
    func testTheSharedPortraitFixtureDecodes() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "portrait", withExtension: "jpg", subdirectory: "Fixtures"),
            "the portrait fixture is missing from the test bundle"
        )
        let data = try Data(contentsOf: url)
        let decoded = try XCTUnwrap(EditorImageDecoder.decode(data))
        XCTAssertGreaterThan(decoded.width, 0)
        XCTAssertGreaterThan(decoded.height, 0)
        XCTAssertEqual(decoded.rgba.count, Int(decoded.width * decoded.height * 4))
    }
}
