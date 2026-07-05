import Foundation
import WeaveCore

/// String Catalog 조회 + 앱 단위 언어 오버라이드.
/// 키는 영어 원문 그대로 — 카탈로그에 없으면 영어가 그대로 노출된다.
enum L10n {
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
            let path = Bundle.module.path(forResource: code, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return .module
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
