import Foundation

/// `.weave` 백업 번들용 zip 압축/해제 — macOS 기본 `ditto` 사용(외부 의존성 없음).
/// 리소스포크·확장속성·격리속성을 빼 `._` 사이드카 없는 깔끔한 아카이브를 만든다.
enum BackupArchive {
    enum ArchiveError: LocalizedError {
        case dittoFailed(Int32)

        var errorDescription: String? {
            switch self {
            case let .dittoFailed(code): return "ditto exited with code \(code)"
            }
        }
    }

    /// 디렉토리의 '내용'을 (부모 폴더 없이) zip으로 압축한다.
    static func zip(contentsOf directory: URL, to destination: URL) throws {
        try run(["--norsrc", "--noextattr", "--noqtn", "-c", "-k", directory.path, destination.path])
    }

    /// zip 아카이브를 디렉토리로 추출한다.
    static func unzip(_ archive: URL, to directory: URL) throws {
        try run(["-x", "-k", archive.path, directory.path])
    }

    private static func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ArchiveError.dittoFailed(process.terminationStatus)
        }
    }
}
