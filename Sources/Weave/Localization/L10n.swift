import Foundation

/// 문자열 조회. 앱은 영어 전용 — 키가 곧 영어 원문이고, `en.lproj`는 문구를 고칠 자리로 남겨 둔다.
enum L10n {
    /// SwiftPM executable resources are copied into the app's Resources directory
    /// by bundle.sh. Use Bundle.main there; keep Bundle.module for swift run/tests.
    static var resourceBundle: Bundle {
        if let url = Bundle.main.url(forResource: "Weave_Weave", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }

    static var bundle: Bundle { resourceBundle }

    /// 날짜·숫자 형식도 영어 화면에 맞춘다(시스템 언어가 한국어여도 "Oct 29").
    static let locale = Locale(identifier: "en_US")
}
