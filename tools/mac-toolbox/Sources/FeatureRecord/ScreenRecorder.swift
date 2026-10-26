import AVFoundation
import ScreenCaptureKit

/// 录屏引擎：ScreenCaptureKit 取画面和声音，AVAssetWriter 写文件（同 iShot 的 SGCaptureSession）
/// 回调都在内部串行队列上，状态只在这个队列里改
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Options {
        let displayID: CGDirectDisplayID
        /// 录制区域：显示器内的点坐标（原点在左上，ScreenCaptureKit 的约定）
        let sourceRect: CGRect
        let pixelScale: CGFloat
        let frameRate: Int
        let showsCursor: Bool
        let showsClicks: Bool
        let systemAudio: Bool
        let microphone: Bool
        let fileType: AVFileType
        let outputURL: URL
    }

    private let queue = DispatchQueue(label: "xtools.recorder")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var clock = PauseClock()

    // MARK: - 开始

    func start(_ options: Options) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == options.displayID }) else {
            throw NSError(domain: "xTools.record", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到要录制的显示器"])
        }
        // 不录 xTools 自己的窗口（录制边框、倒计时等）
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        // 视频宽高取偶数，H.264 要求
        let width = Int(options.sourceRect.width * options.pixelScale) / 2 * 2
        let height = Int(options.sourceRect.height * options.pixelScale) / 2 * 2
        let config = SCStreamConfiguration()
        config.sourceRect = options.sourceRect
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
        config.showsCursor = options.showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        config.capturesAudio = options.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        if #available(macOS 15.0, *) {
            config.showMouseClicks = options.showsClicks
            config.captureMicrophone = options.microphone
        }

        let writer = try AVAssetWriter(outputURL: options.outputURL, fileType: options.fileType)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)
        let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                                            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000]
        if options.systemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        }
        if options.microphone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            micInput = input
        }
        self.writer = writer
        videoInput = video

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if options.systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        if options.microphone, #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
        self.stream = stream
        try await stream.startCapture()
    }

    // MARK: - 暂停、停止

    func setPaused(_ paused: Bool) {
        queue.async { paused ? self.clock.pause() : self.clock.resume() }
    }

    /// 停止并写完文件；没有录到任何画面时返回 nil
    func stop() async -> URL? {
        try? await stream?.stopCapture()
        stream = nil
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let writer = self.writer, self.sessionStarted else {
                    self.writer?.cancelWriting()
                    continuation.resume(returning: nil)
                    return
                }
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                self.micInput?.markAsFinished()
                writer.finishWriting {
                    continuation.resume(returning: writer.status == .completed ? writer.outputURL : nil)
                }
            }
        }
    }

    // MARK: - SCStreamOutput（在 queue 上回调）

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let writer, sampleBuffer.isValid else { return }
        if type == .screen {
            // 只要完整的画面帧（画面没变化时 ScreenCaptureKit 会发空帧）
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        }
        // 第一帧画面到了才开始写，音频不能早于画面
        if !sessionStarted {
            guard type == .screen else { return }
            writer.startWriting()
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            sessionStarted = true
        }
        guard let time = clock.adjust(sampleBuffer.presentationTimeStamp),
              let buffer = retimed(sampleBuffer, to: time) else { return }

        let input: AVAssetWriterInput?
        switch type {
        case .screen: input = videoInput
        case .audio: input = audioInput
        default: input = micInput
        }
        if let input, input.isReadyForMoreMediaData { input.append(buffer) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[record] 录制中断：\(error)")
    }

    /// 暂停过就要把时间往前挪；没暂停过直接用原帧
    private func retimed(_ buffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        guard time != buffer.presentationTimeStamp else { return buffer }
        var timing = CMSampleTimingInfo(duration: buffer.duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: 1,
                                              sampleTimingArray: &timing, sampleBufferOut: &result)
        return result
    }
}
