import Foundation
import AVFoundation
import AppKit

@MainActor
public final class FFmpegConverter {
    public static let shared = FFmpegConverter()

    public static let ffmpegURL: URL? = FFmpegConverter.locate("ffmpeg")
    public static let ffprobeURL: URL? = FFmpegConverter.locate("ffprobe")

    public static let remuxProfile = ["-c:v", "copy", "-pix_fmt", "yuv420p",
                                      "-movflags", "+faststart"]
    public static let aacFallback = ["-c:a", "aac_at", "-b:a", "128k"]

    public private(set) var currentProcess: Process?
    private var processQueue: [URL] = []

    private static func locate(_ tool: String) -> URL? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    public func remuxIfNeeded(_ url: URL) async -> URL? {
        guard let ffmpeg = Self.ffmpegURL else { return nil }
        let out = url.deletingLastPathComponent()
            .appendingPathComponent("ray-lite-\(UUID().uuidString.prefix(8)).mp4")
        return await withCheckedContinuation { [weak self] cont in
            let proc = Process()
            proc.executableURL = ffmpeg
            proc.arguments = ["-y", "-i", url.path] + Self.remuxProfile + [out.path]
            proc.standardError = FileHandle.nullDevice
            Task { @MainActor in self?.currentProcess = proc }
            proc.terminationHandler = { [weak self] _ in
                Task { @MainActor in self?.currentProcess = nil }
                cont.resume(returning: FileManager.default.fileExists(atPath: out.path) ? out : nil)
            }
            try? proc.run()
        }
    }

    public func probe(_ url: URL) async -> (duration: Double, tracks: Int) {
        guard let ffprobe = Self.ffprobeURL else { return (0, 0) }
        let proc = Process()
        proc.executableURL = ffprobe
        proc.arguments = ["-show_streams", "-of", "json", url.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        while proc.isRunning { usleep(20_000) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let streams = root?["streams"] as? [[String: Any]] ?? []
        let duration = (streams.first?["duration"] as? String).flatMap(Double.init) ?? 0
        return (duration, streams.count)
    }
}

@MainActor
public final class VideoPlayerItem: CALayer {
    private var looper: AVPlayerLooper?

    public init(assetURL: URL, looping: Bool = true) {
        super.init()
        let queue = AVQueuePlayer()
        let playerLayer = AVPlayerLayer(player: queue)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        addSublayer(playerLayer)
        if looping, let base = AVPlayerItem(url: assetURL) as AVPlayerItem? {
            let looper = AVPlayerLooper(player: queue, templateItem: base)
            self.looper = looper
            queue.play()
        }
    }

    required init?(coder: NSCoder) { nil }
}
