// Records one app's largest window to an mp4, covered or not, until a stop file appears. Prints the window's frame
// ("window x y width height scale", in points) and the wall-clock time of the first frame ("start <seconds>"), which
// the edit lines the app's events.tsv up against. Needs Screen & System Audio Recording for whatever runs it.
//   record <pid> <out.mp4> <stop file>
import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

// ScreenCaptureKit needs a connection to the window server, which a plain command-line program makes only once asked.
_ = NSApplication.shared

let arguments = CommandLine.arguments
guard arguments.count == 4, let pid = pid_t(arguments[1]) else {
    print("record <pid> <out.mp4> <stop file>"); exit(2)
}
let out = URL(fileURLWithPath: arguments[2])
let stop = arguments[3]

final class Recorder: NSObject, SCStreamOutput, @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    private var started = false

    init(width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: out)
        writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 24_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only frames with something new: an idle window sends none, which the edit fills by holding the last.
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        if !started {
            started = true
            writer.startWriting()
            writer.startSession(atSourceTime: time)
            // A frame's time is the host clock's; the app logs the wall clock's.
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            print(String(format: "start %.3f", Date().timeIntervalSince1970 - (now - time).seconds)); fflush(stdout)
        }
        if input.isReadyForMoreMediaData { input.append(buffer) }
    }
}

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.filter({ $0.owningApplication?.processID == pid && $0.windowLayer == 0 })
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            print("no window"); exit(1)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = false
        configuration.queueDepth = 8
        print(String(format: "window %.0f %.0f %.0f %.0f %.0f", window.frame.minX, window.frame.minY,
                     window.frame.width, window.frame.height, scale)); fflush(stdout)
        let recorder = try Recorder(width: configuration.width, height: configuration.height)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
        try await stream.startCapture()
        while !FileManager.default.fileExists(atPath: stop) { try await Task.sleep(for: .milliseconds(200)) }
        try await stream.stopCapture()
        recorder.input.markAsFinished()
        await recorder.writer.finishWriting()
        print("done", recorder.writer.error?.localizedDescription ?? ""); fflush(stdout)
        exit(recorder.writer.status == .completed ? 0 : 1)
    } catch {
        print("failed", error.localizedDescription); exit(1)
    }
}
RunLoop.main.run()
