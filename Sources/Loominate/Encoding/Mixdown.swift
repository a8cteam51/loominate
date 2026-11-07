import AVFoundation

/// Turns the intermediate .mov (video + up to two audio tracks) into the final .mp4
/// with exactly one audio track. Video is passed through untouched.
enum Mixdown {
    /// `gains` are applied by audio track index when more than one track exists.
    static func run(input: URL, output: URL, gains: [Float]) async throws {
        let asset = AVURLAsset(url: input)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw RecordingError.noVideoTrack }

        var audioTracks: [AVAssetTrack] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            let range = try await track.load(.timeRange)
            if range.duration.seconds > 0 { audioTracks.append(track) }
        }

        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        // Video passthrough.
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw RecordingError.mixdownFailed("cannot read video") }
        reader.add(videoOutput)
        let videoFormat = try await videoTrack.load(.formatDescriptions).first
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw RecordingError.mixdownFailed("cannot write video") }
        writer.add(videoInput)

        // Audio: passthrough for one track, decode + mix + AAC for several.
        var audioPair: (AVAssetReaderOutput, AVAssetWriterInput)?
        if audioTracks.count == 1 {
            let track = audioTracks[0]
            let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            out.alwaysCopiesSampleData = false
            let format = try await track.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(out), writer.canAdd(input) else { throw RecordingError.mixdownFailed("cannot pass audio through") }
            reader.add(out)
            writer.add(input)
            audioPair = (out, input)
        } else if audioTracks.count > 1 {
            let out = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: CodecSettings.pcmStereo())
            out.alwaysCopiesSampleData = false
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioTracks.enumerated().map { index, track in
                let params = AVMutableAudioMixInputParameters(track: track)
                let gain = index < gains.count ? gains[index] : 1
                params.setVolume(gain, at: .zero)
                return params
            }
            out.audioMix = mix
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: CodecSettings.audio(channels: 2))
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(out), writer.canAdd(input) else { throw RecordingError.mixdownFailed("cannot mix audio") }
            reader.add(out)
            writer.add(input)
            audioPair = (out, input)
        }

        guard reader.startReading() else { throw reader.error ?? RecordingError.mixdownFailed("reader did not start") }
        guard writer.startWriting() else { throw writer.error ?? RecordingError.mixdownFailed("writer did not start") }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "com.automattic.loominate.mixdown")
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await pump(from: videoOutput, to: videoInput, on: queue) }
            if let (out, input) = audioPair {
                group.addTask { await pump(from: out, to: input, on: queue) }
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? RecordingError.mixdownFailed("reader failed")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? RecordingError.mixdownFailed("writer status \(writer.status.rawValue)")
        }
        Log.note("mixdown wrote \(output.lastPathComponent) from \(audioTracks.count) audio track(s)")
    }

    private static func pump(from output: AVAssetReaderOutput, to input: AVAssetWriterInput, on queue: DispatchQueue) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if let sample = output.copyNextSampleBuffer() {
                        if !input.append(sample) {
                            Log.mixdown.error("append failed during mixdown")
                            input.markAsFinished()
                            continuation.resume()
                            return
                        }
                    } else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }
}
