import AVFoundation
import Combine

@MainActor
final class MudVoice: ObservableObject {
    @Published var recording = false
    @Published var busy = false
    @Published var playing = false
    @Published var level: Double = 0
    @Published var status = "播放录音"
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var meter: Timer?
    private let pcmURL = FileManager.default.temporaryDirectory.appendingPathComponent("jiuzhou-recording.wav")
    private let playbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("jiuzhou-playback.wav")
    private var lastAMR: Data?
    private var generation = UUID()

    func start() {
        guard !recording && !busy else { return }
        busy = true
        let token = generation
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                defer { self.busy = false }
                guard allowed else { self.status = "未允许麦克风访问"; return }
                do {
                    self.player?.stop(); self.playing = false
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)
                    self.recorder = try AVAudioRecorder(url: self.pcmURL, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
                    self.recorder?.isMeteringEnabled = true
                    guard self.recorder?.record() == true else { throw VoiceCodec.Failure.unavailable }
                    self.recording = true; self.status = "录音中"
                    self.meter?.invalidate()
                    self.meter = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                        guard let model = self else { return }
                        Task { @MainActor in
                            model.recorder?.updateMeters()
                            model.level = pow(10, Double(model.recorder?.averagePower(forChannel: 0) ?? -160) / 20)
                        }
                    }
                } catch { self.status = "录音失败"; self.cancel() }
            }
        }
    }

    func finish(send: @escaping (String) -> Void) {
        guard recording else { return }
        let duration = recorder?.currentTime ?? 0
        recorder?.stop(); recording = false; meter?.invalidate(); level = 0
        guard duration >= 1 else { status = "录音时间太短"; return }
        busy = true; status = "正在发送"
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let file = try AVAudioFile(forReading: pcmURL)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw VoiceCodec.Failure.unavailable }
                try file.read(into: buffer)
                guard let channel = buffer.floatChannelData?[0] else { throw VoiceCodec.Failure.unavailable }
                let samples = (0..<Int(buffer.frameLength)).map { Int16(max(-32768, min(32767, Double(channel[$0]) * 32767))) }
                let amr = try VoiceCodec.encode(samples)
                lastAMR = amr
                let filename = String(Int64(Date().timeIntervalSince1970 * 1000)) + ".amr"
                guard let request = LegacyService.voiceUpload(amr, filename: filename) else { throw VoiceCodec.Failure.invalidAMR }
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" else {
                    status = "发送失败"; return
                }
                send("liaotian voice " + filename)
                status = "语音消息发送成功"
            } catch is CancellationError { }
            catch { status = "发送失败，请检查网络" }
        }
    }

    func play(filename: String? = nil) {
        guard !recording else { return }
        if playing { player?.stop(); playing = false; status = "播放录音"; return }
        task?.cancel()
        task = Task { @MainActor in
            busy = true
            defer { busy = false }
            do {
                if let filename {
                    guard let url = LegacyService.voiceURL(filename) else { throw VoiceCodec.Failure.invalidAMR }
                    status = "准备下载"
                    let (data, response) = try await URLSession.shared.data(from: url)
                    try Task.checkCancellation()
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw VoiceCodec.Failure.invalidAMR }
                    lastAMR = data
                }
                guard let amr = lastAMR else { status = "暂无录音"; return }
                let samples = try VoiceCodec.decode(amr)
                guard !samples.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1),
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                      let channel = buffer.floatChannelData?[0] else { throw VoiceCodec.Failure.invalidAMR }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                for index in samples.indices { channel[index] = Float(samples[index]) / 32768 }
                do {
                    let file = try AVAudioFile(forWriting: playbackURL, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16])
                    try file.write(from: buffer)
                }
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback)
                try session.setActive(true)
                player = try AVAudioPlayer(contentsOf: playbackURL)
                guard player?.play() == true else { throw VoiceCodec.Failure.unavailable }
                playing = true; status = "停止播放"
                let duration = player?.duration ?? 0
                busy = false
                try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
                if !Task.isCancelled { playing = false; status = "播放录音" }
            } catch is CancellationError { }
            catch { playing = false; status = "播放失败" }
        }
    }

    func cancel() {
        generation = UUID()
        task?.cancel(); task = nil
        recorder?.stop(); player?.stop(); meter?.invalidate()
        recording = false; playing = false; busy = false; level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
