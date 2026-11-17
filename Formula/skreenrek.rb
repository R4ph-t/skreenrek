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
      Copy the app into ~/Applications (Spotlight, Launchpad and Finder's
      Applications view skip symlinks). Redo this after each brew upgrade:
        mkdir -p ~/Applications
        rm -rf ~/Applications/Skreenrek.app
        cp -R #{opt_prefix}/Skreenrek.app ~/Applications/Skreenrek.app
      Open it once to grant Screen Recording and Accessibility:
        open ~/Applications/Skreenrek.app
      Connect your agents:
        skreenrek setup agents

      Skreenrek is ad-hoc signed, and each rebuild changes the signature, so
      macOS forgets the grants after an upgrade. Reset them, then reopen the
      app and allow both again:
        tccutil reset ScreenCapture it.fraime.skreenrek
        tccutil reset Accessibility it.fraime.skreenrek
    EOS
  end

  test do
    assert_match "skreenrek", shell_output("#{bin}/skreenrek --version")
  end
end
