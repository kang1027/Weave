import Foundation
import WeaveCore

/// String Catalog 조회 + 앱 단위 언어 오버라이드.
/// 키는 영어 원문 그대로 — 카탈로그에 없으면 영어가 그대로 노출된다.
enum L10n {
    /// SwiftPM executable resources are copied into the app's Resources directory
    /// by bundle.sh. Use Bundle.main there; keep Bundle.module for swift run/tests.
    private static var resourceBundle: Bundle {
        if let url = Bundle.main.url(forResource: "Weave_Weave", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }

    /// 언어 설정에 맞는 리소스 번들. `.system`이면 시스템 로케일 규칙.
    static func bundle(for preference: LanguagePreference) -> Bundle {
        let code: String?
        switch preference {
        case .system: code = nil
        case .korean: code = "ko"
        case .english: code = "en"
        }
        guard
            let code,
            let path = resourceBundle.path(forResource: code, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return resourceBundle
        }
        return bundle
    }

    static func locale(for preference: LanguagePreference) -> Locale {
        switch preference {
        case .system: return .autoupdatingCurrent
        case .korean: return Locale(identifier: "ko_KR")
        case .english: return Locale(identifier: "en_US")
        }
    }
}
