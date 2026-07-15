import AppKit
import WeaveCore

/// 사용자 업로드 자산 로고 — `Application Support/Weave/logos/` 아래 PNG로 저장.
/// 파일명에 타임스탬프를 넣어 교체 시 캐시가 자연 무효화된다. UI 전용(@MainActor).
@MainActor
enum LogoStore {
    private static let cache = NSCache<NSString, NSImage>()
    private static let maxDimension: CGFloat = 256

    static var directory: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(WeaveInfo.appName, isDirectory: true)
            .appendingPathComponent("logos", isDirectory: true)
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// 이미지 파일을 읽어 256px 이하 PNG로 저장하고 파일명을 돌려준다.
    static func saveLogo(from sourceURL: URL, assetID: UUID) throws -> String {
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let resized = downscale(image, maxDimension: maxDimension)
        guard
            let tiff = resized.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(assetID.uuidString)-\(Int(Date().timeIntervalSince1970)).png"
        try png.write(to: url(for: fileName), options: .atomic)
        return fileName
    }

    static func delete(fileName: String?) {
        guard let fileName else { return }
        cache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    static func clearAll() {
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
    }

    static func image(named fileName: String) -> NSImage? {
        if let cached = cache.object(forKey: fileName as NSString) {
            return cached
        }
        guard let image = NSImage(contentsOf: url(for: fileName)) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }

    private static func downscale(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: target)
        result.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }
}
