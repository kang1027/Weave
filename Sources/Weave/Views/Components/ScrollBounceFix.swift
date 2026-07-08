import AppKit
import SwiftUI

/// 세로 스크롤뷰가 가로 두 손가락 스와이프에 고무줄처럼 튕기는 것을 막는다.
/// SwiftUI `scrollBounceBehavior`가 macOS 가로축엔 잘 안 먹어서 NSScrollView 탄성을 직접 끈다.
/// ScrollView '내용물' 안에 넣어야 `enclosingScrollView`로 상위 스크롤뷰를 찾을 수 있다.
private struct HorizontalBounceDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(from: nsView)
    }

    private func apply(from view: NSView) {
        // 뷰 계층에 붙은 뒤 상위 NSScrollView를 찾아 가로 탄성만 끈다(세로는 그대로).
        DispatchQueue.main.async { [weak view] in
            guard let scrollView = view?.enclosingScrollView else { return }
            scrollView.horizontalScrollElasticity = .none
            scrollView.hasHorizontalScroller = false
        }
    }
}

extension View {
    /// ScrollView 내용물에 붙여 가로 바운스를 제거한다.
    func disableHorizontalScrollBounce() -> some View {
        background(HorizontalBounceDisabler().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
