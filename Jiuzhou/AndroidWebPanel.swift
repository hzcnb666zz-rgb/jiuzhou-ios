import SwiftUI
import WebKit

private struct MudWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct AndroidWebPanel: View {
    let url: URL
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            MudWebView(url: url).id(url)
            Button("关闭", action: close).frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(white: 0.14)).foregroundStyle(.white)
        }.background(.white)
    }
}
