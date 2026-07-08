import AppKit
import SwiftUI

/// 세로 스크롤뷰/팝오버가 트랙패드 가로 스와이프에 고무줄처럼 튕기는 것을 막는다.
/// 원인: 트랙패드 가로 스크롤휠 이벤트를 SwiftUI 스크롤뷰가 가로 오버스크롤로 처리(탄성 설정 무시).
/// 대책: (1) NSScrollView 가로 탄성 끄기 + (2) '가로 우세' 정밀 스크롤 이벤트를 삼키기.
///       이 앱엔 가로 스크롤 콘텐츠가 없으므로 세로 스크롤엔 영향 없다.
private struct HorizontalBounceDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BounceFixView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? BounceFixView)?.applyFix()
    }
}

private final class BounceFixView: NSView {
    /// 앱 전역 1개만 — 가로 우세 정밀 스크롤 이벤트를 삼킨다.
    private static var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyFix()
        Self.installScrollMonitorOnce()
    }

    func applyFix() {
        guard let window else { return }
        Self.disableHorizontalElasticity(in: window.contentView)
    }

    private static func installScrollMonitorOnce() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // 트랙패드(정밀 델타)의 가로 우세 스크롤만 삼킨다 — 세로/마우스휠은 그대로.
            guard event.hasPreciseScrollingDeltas else { return event }
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                return nil
            }
            return event
        }
    }

    private static func disableHorizontalElasticity(in view: NSView?) {
        guard let view else { return }
        if let scrollView = view as? NSScrollView {
            scrollView.horizontalScrollElasticity = .none
            scrollView.hasHorizontalScroller = false
            scrollView.usesPredominantAxisScrolling = true
        }
        for subview in view.subviews {
            disableHorizontalElasticity(in: subview)
        }
    }
}

extension View {
    /// 가로 바운스를 제거한다(창 전체 스크롤뷰 대상 + 가로 스크롤 이벤트 억제).
    func disableHorizontalScrollBounce() -> some View {
        background(HorizontalBounceDisabler().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
