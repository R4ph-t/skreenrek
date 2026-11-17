class Skreenrek < Formula
  desc "Record a macOS window at an exact pixel size"
  homepage "https://github.com/R4ph-t/skreenrek"
  license "MIT"
  head "https://github.com/R4ph-t/skreenrek.git", branch: "main"

  depends_on macos: :sequoia
  depends_on xcode: ["16.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox", "--product", "skreenrek"
    system "bash", "scripts/bundle-app.sh", ".build/release", prefix
    bin.install_symlink prefix/"Skreenrek.app/Contents/MacOS/skreenrek"
  end

  def caveats
    <<~EOS
      Link the app into ~/Applications:
        mkdir -p ~/Applications
        ln -sfn #{opt_prefix}/Skreenrek.app ~/Applications/Skreenrek.app
      Open it once to grant Screen Recording and Accessibility:
        open ~/Applications/Skreenrek.app
      Connect your agents:
        skreenrek setup agents

      Skreenrek is ad-hoc signed. macOS may ask for Screen Recording and
      Accessibility again after an upgrade.
    EOS
  end

  test do
    assert_match "skreenrek", shell_output("#{bin}/skreenrek --version")
  end
end
