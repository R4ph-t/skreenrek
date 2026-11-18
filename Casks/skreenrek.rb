cask "skreenrek" do
  version "1.0.4"
  sha256 "59f5e432df815aedb5893776e623f848c5c7094a7ba61c22dc37e1fbe0404995"

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

  uninstall quit: "it.fraime.skreenrek"

  zap trash: [
    "~/Library/Application Support/skreenrek",
    "~/Library/Caches/it.fraime.skreenrek",
    "~/Library/HTTPStorages/it.fraime.skreenrek",
    "~/Library/Preferences/it.fraime.skreenrek.plist",
    "~/Library/Saved Application State/it.fraime.skreenrek.savedState",
  ]

  caveats <<~EOS
    Open Skreenrek once to grant Screen Recording and Accessibility:
      open /Applications/Skreenrek.app
    Then connect your agents:
      skreenrek setup agents
  EOS
end
