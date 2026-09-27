import SwiftUI
import AVFoundation

/// 黑底云雾视频播放器：用 Screen（滤色）混合叠加时，纯黑部分会变透明，
/// 只留下云雾飘在下层画面上。
final class TransitionPlayer {
    let player: AVPlayer
    private let item: AVPlayerItem
    init?(name: String, ext: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .none
        p.isMuted = true
        self.item = item
        self.player = p
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in
            p.seek(to: .zero)
            p.play()
        }
    }
    func start() { player.seek(to: .zero); player.play() }
    func stop() { player.pause() }
}

final class CloudPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var player: AVPlayer? {
        get { (layer as? AVPlayerLayer)?.player }
        set { (layer as? AVPlayerLayer)?.player = newValue }
    }
}

/// 云雾转场：铺满屏幕叠在下层画面上，黑底用滤色消失，只留云雾。
/// 自动淡入 -> 飘一会 -> 淡出 -> 回调结束。
struct CloudTransitionOverlay: View {
    let onFinished: () -> Void
    private let duration: TimeInterval = 3.0
    @State private var player: TransitionPlayer?
    @State private var appear = false

    var body: some View {
        ZStack {
            if let p = player {
                CloudLayer(player: p.player)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .opacity(appear ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            if player == nil { player = TransitionPlayer(name: "wuyun", ext: "mp4") }
            player?.start()
            // 快速盖住（0.25s），让切屏发生在云后面；背后加载好后再缓缓散开（0.9s）。
            withAnimation(.easeIn(duration: 0.25)) { appear = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.easeOut(duration: 0.9)) { appear = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { onFinished() }
            }
        }
    }
}

private struct CloudLayer: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> CloudPlayerLayerView {
        let v = CloudPlayerLayerView()
        v.player = player
        (v.layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: CloudPlayerLayerView, context: Context) {}
}
