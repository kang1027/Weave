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
        // 창 전체의 모든 NSScrollView 가로 탄성을 끈다(세로는 그대로).
        // MenuBarExtra(.window) 팝오버는 콘텐츠를 바깥쪽 스크롤뷰로 감싸므로,
        // 내 스크롤뷰(enclosingScrollView)만 끄면 바깥쪽이 계속 튕긴다.
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            Self.disableHorizontal(in: window.contentView)
        }
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
    /// ScrollView 내용물에 붙여 가로 바운스를 제거한다.
    func disableHorizontalScrollBounce() -> some View {
        background(HorizontalBounceDisabler().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
