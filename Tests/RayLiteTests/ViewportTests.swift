import AppKit
import Testing
@testable import RayLite

struct ViewportTests {
    @Test(arguments: [0.3, 1.0, 4.0])
    func pointAndRectRoundTrip(scale: Double) {
        var viewport = Viewport(scale: scale)
        let point = CGPoint(x: -127.25, y: 653.75)
        let rect = CGRect(x: -123, y: 97, width: 241, height: 153)
        for delta in [CGSize.zero, CGSize(width: -912.5, height: 731.25)] {
            viewport.pan(by: delta)
            let actual = viewport.canvasPoint(fromView: viewport.viewPoint(fromCanvas: point))
            #expect(abs(actual.x - point.x) < 0.000001)
            #expect(abs(actual.y - point.y) < 0.000001)
            let actualRect = viewport.canvasRect(fromView: viewport.viewRect(fromCanvas: rect))
            #expect(abs(actualRect.minX - rect.minX) < 0.000001)
            #expect(abs(actualRect.minY - rect.minY) < 0.000001)
            #expect(abs(actualRect.width - rect.width) < 0.000001)
            #expect(abs(actualRect.height - rect.height) < 0.000001)
            #expect(viewport.viewPoint(fromCanvas: point) == point.applying(viewport.transform))
        }
    }

    @Test(arguments: [0.3, 1.0, 4.0])
    func neutralPinchPreservesViewport(scale: Double) {
        var viewport = Viewport(scale: scale, translation: CGPoint(x: -80, y: 125))
        let initial = viewport
        viewport.magnify(by: 0, at: CGPoint(x: 751, y: 83))
        #expect(viewport.scale == initial.scale)
        #expect(abs(viewport.translation.x - initial.translation.x) < 0.000001)
        #expect(abs(viewport.translation.y - initial.translation.y) < 0.000001)
    }

    @Test(arguments: [0.3, 1.0, 4.0], [-2.0, -0.25, 0.5, 20.0])
    func pinchKeepsAnchorAndClampsScale(scale: Double, magnification: Double) {
        var viewport = Viewport(scale: scale, translation: CGPoint(x: 582, y: -342))
        let pointer = CGPoint(x: 731, y: 215)
        let anchor = viewport.canvasPoint(fromView: pointer)
        viewport.magnify(by: magnification, at: pointer)
        let actual = viewport.viewPoint(fromCanvas: anchor)
        #expect(hypot(actual.x - pointer.x, actual.y - pointer.y) < 2)
        let expected = min(max(CGFloat(scale) * (1 + CGFloat(magnification)), 0.3), 4)
        #expect(abs(viewport.scale - expected) < 0.000001)
        #expect((0.3...4).contains(viewport.scale))
    }

    @Test func panHasNoBoundsAndUsesEachDeltaOnce() {
        var viewport = Viewport()
        for delta in [CGSize(width: -1000, height: 2000), CGSize(width: 2500, height: -4500),
                      CGSize(width: -3000, height: 5000)] {
            viewport.pan(by: delta)
        }
        #expect(viewport.translation == CGPoint(x: -1500, y: 2500))
        #expect(viewport.scale == 1)
        #expect(Viewport(scale: -2).scale == 0.3)
        #expect(Viewport(scale: 100).scale == 4)
    }

    @Test func decodesPinchAndMomentum() throws {
        let steps = try JSONDecoder().decode([VerifyStep].self, from: Data("""
        [{"kind":"pinch","x":120,"y":340,"magnification":0.5},
         {"kind":"scroll","dx":-8,"dy":13,"momentumPhase":"changed","precise":false}]
        """.utf8))
        guard case .pinch(let point, let magnification, let phase) = steps[0].action else {
            Issue.record("The decoder must preserve the pinch action.")
            return
        }
        #expect(point == CGPoint(x: 120, y: 340))
        #expect(magnification == 0.5)
        #expect(phase.isEmpty)
        guard case .scroll(let dx, let dy, let scrollPhase, let momentumPhase, let precise) = steps[1].action else {
            Issue.record("The decoder must preserve the scroll action.")
            return
        }
        #expect(dx == -8 && dy == 13)
        #expect(scrollPhase.isEmpty && momentumPhase == .changed)
        #expect(!precise)
    }
}
