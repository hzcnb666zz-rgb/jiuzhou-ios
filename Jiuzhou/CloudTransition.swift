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

/// 云雾转场：云雾盖住登录页飘一会儿 → 黑底渐入压成全黑 → 在黑底后揭晓新界面 → 黑底淡出。
/// onReveal 在屏幕全黑时回调（新界面在黑底下揭晓，用户无感）；
/// onFinished 在黑底完全淡出后回调（此时可把转场层移除）。
struct CloudTransitionOverlay: View {
    let onReveal: () -> Void
    let onFinished: () -> Void
    private let cloudAppearIn: TimeInterval = 0.25  // 云雾淡入盖住登录页
    private let cloudSettle: TimeInterval = 2.4    // 云雾飘一会
    private let blackIn: TimeInterval = 0.9         // 黑底渐入压成全黑
    private let blackOut: TimeInterval = 0.9        // 黑底淡出揭晓新界面
    @State private var player: TransitionPlayer?
    @State private var cloudAppear = false
    @State private var blackOpacity: Double = 0
    @State private var revealed = false

    var body: some View {
        ZStack {
            if let p = player {
                CloudLayer(player: p.player)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .opacity(cloudAppear ? 1 : 0)
            }
            Color.black
                .opacity(blackOpacity)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            if player == nil { player = TransitionPlayer(name: "wuyun", ext: "mp4") }
            player?.start()
            withAnimation(.easeIn(duration: cloudAppearIn)) { cloudAppear = true }
            // 云雾飘一会后，黑底渐入压成全黑
            DispatchQueue.main.asyncAfter(deadline: .now() + cloudAppearIn + cloudSettle) {
                withAnimation(.easeIn(duration: blackIn)) { blackOpacity = 1 }
                // 全黑的瞬间揭晓新界面（此时完全被黑层盖住，切换无感）
                DispatchQueue.main.asyncAfter(deadline: .now() + blackIn) {
                    if !revealed { revealed = true; onReveal() }
                    // 黑底缓缓淡出，露出新界面
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: blackOut)) { blackOpacity = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + blackOut + 0.05) { onFinished() }
                    }
                }
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
