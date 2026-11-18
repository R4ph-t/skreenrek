cask "skreenrek" do
  version "1.0.5"
  sha256 "bcaa3ff72227a3cbe5cf4871517052683f40bd5a5dfee3906f876fcc9a2956d7"

  url "https://github.com/R4ph-t/skreenrek/releases/download/v#{version}/Skreenrek-#{version}.zip"
  name "Skreenrek"
  desc "Record a macOS window at an exact pixel size"
  homepage "https://github.com/R4ph-t/skreenrek"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "Skreenrek.app"
  binary "#{appdir}/Skreenrek.app/Contents/MacOS/skreenrek"

  uninstall quit: "com.raphaelterrier.skreenrek"

  zap trash: [
    "~/Library/Application Support/skreenrek",
    "~/Library/Caches/com.raphaelterrier.skreenrek",
    "~/Library/Caches/it.fraime.skreenrek",
    "~/Library/HTTPStorages/com.raphaelterrier.skreenrek",
    "~/Library/HTTPStorages/it.fraime.skreenrek",
    "~/Library/Preferences/com.raphaelterrier.skreenrek.plist",
    "~/Library/Preferences/it.fraime.skreenrek.plist",
    "~/Library/Saved Application State/com.raphaelterrier.skreenrek.savedState",
    "~/Library/Saved Application State/it.fraime.skreenrek.savedState",
  ]

  caveats <<~EOS
    Open Skreenrek once to grant Screen Recording and Accessibility:
      open /Applications/Skreenrek.app
    Then connect your agents:
      skreenrek setup agents
  EOS
end
