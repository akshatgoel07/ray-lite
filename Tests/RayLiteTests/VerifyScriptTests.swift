import AppKit
import Foundation
import Testing
@testable import RayLite

struct VerifyScriptTests {
    @Test func decodesMouseSequenceWithModifiers() throws {
        let data = Data("""
        [{"kind":"drag","from":{"x":12,"y":34},"to":{"x":56,"y":78},"steps":8,"modifiers":["shift","command"]}]
        """.utf8)
        let step = try #require(JSONDecoder().decode([VerifyStep].self, from: data).first)
        guard case .drag(let start, let end, let count) = step.action else {
            Issue.record("The decoder must preserve the drag action.")
            return
        }
        #expect(start == CGPoint(x: 12, y: 34))
        #expect(end == CGPoint(x: 56, y: 78))
        #expect(count == 8)
        #expect(step.modifiers == [.shift, .command])
    }

    @Test(arguments: [15, 60])
    func decodesRecordingRate(fps: Int) throws {
        let data = Data("[{\"kind\":\"record\",\"path\":\"/tmp/frames\",\"fps\":\(fps)}]".utf8)
        let step = try #require(JSONDecoder().decode([VerifyStep].self, from: data).first)
        guard case .record(let path, let rate, _) = step.action else {
            Issue.record("The decoder must preserve the record action.")
            return
        }
        #expect(path == "/tmp/frames")
        #expect(rate == fps)
    }

    @Test(arguments: [
        "[{\"kind\":\"drag\",\"from\":{\"x\":0,\"y\":0},\"to\":{\"x\":1,\"y\":1},\"steps\":0}]",
        "[{\"kind\":\"key\"}]",
        "[{\"kind\":\"wait\",\"ms\":-1}]",
        "[{\"kind\":\"resize\",\"w\":0,\"h\":380}]",
        "[{\"kind\":\"click\",\"x\":0,\"y\":0,\"modifiers\":[\"unknown\"]}]",
        "[{\"kind\":\"scroll\",\"dx\":0,\"dy\":1,\"phase\":\"unknown\"}]",
        "[{\"kind\":\"axAction\",\"name\":\"Note\",\"text\":\"unknown\"}]",
        "[{\"kind\":\"record\",\"path\":\"/tmp/frames\",\"fps\":0}]",
        "[{\"kind\":\"unknown\"}]"
    ])
    func rejectsInvalidSteps(script: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([VerifyStep].self, from: Data(script.utf8))
        }
    }
}
