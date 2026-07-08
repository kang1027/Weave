# Homebrew cask 템플릿 — kang1027/homebrew-weave 리포의 Casks/weave-pt.rb 로 복사해 쓴다.
# 릴리즈마다 version 과 sha256 을 갱신할 것.
#   sha256:  shasum -a 256 dist/Weave-<version>.zip
cask "weave-pt" do
  version "0.1.0"
  sha256 "REPLACE_WITH_ZIP_SHA256"

  url "https://github.com/kang1027/Weave/releases/download/v#{version}/Weave-#{version}.zip"
  name "Weave"
  desc "Menu-bar portfolio tracker"
  homepage "https://github.com/kang1027/Weave"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Weave.app"

  zap trash: [
    "~/Library/Application Support/Weave",
    "~/Library/Caches/app.weave",
    "~/Library/Preferences/app.weave.plist",
  ]
end
