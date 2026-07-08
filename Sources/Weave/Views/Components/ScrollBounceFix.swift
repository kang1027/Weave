import AppKit
import SwiftUI

/// 세로 스크롤뷰/팝오버가 가로 두 손가락 스와이프에 고무줄처럼 튕기는 것을 막는다.
/// SwiftUI `scrollBounceBehavior`가 macOS 가로축엔 잘 안 먹어서 NSScrollView 탄성을 직접 끈다.
private struct HorizontalBounceDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BounceFixView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? BounceFixView)?.applyFix()
    }
}

/// 창에 붙는 즉시(그리고 갱신마다) 창 전체 NSScrollView의 가로 탄성을 끈다.
private final class BounceFixView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyFix()
    }

    func applyFix() {
        guard let window else { return }
        Self.disableHorizontal(in: window.contentView)
    }

    private static func disableHorizontal(in view: NSView?) {
        guard let view else { return }
        if let scrollView = view as? NSScrollView {
            scrollView.horizontalScrollElasticity = .none
            scrollView.hasHorizontalScroller = false
            // 스크롤을 우세 축(세로)으로 고정 — 대각/가로 성분을 무시해 옆으로 밀리지 않게.
            scrollView.usesPredominantAxisScrolling = true
        }
        for subview in view.subviews {
            disableHorizontal(in: subview)
        }
    }
}

extension View {
    /// 가로 바운스를 제거한다(창 전체 스크롤뷰 대상).
    func disableHorizontalScrollBounce() -> some View {
        background(HorizontalBounceDisabler().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
