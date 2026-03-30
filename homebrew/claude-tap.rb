class ClaudeTap < Formula
  desc "Dynamic Island-style notifications, sound alerts and status line for Claude Code"
  homepage "https://github.com/EdoardoCroci/claude-tap"
  url "https://github.com/EdoardoCroci/claude-tap.git", branch: "main"
  version "1.1.0"
  license "MIT"

  depends_on :macos
  depends_on "jq"

  def install
    prefix.install Dir["*"]
  end

  def post_install
    system "#{prefix}/macos/setup.sh", prefix.to_s, "--quiet"
  end

  def caveats
    msg = <<~EOS
      Claude Tap is ready to use! Restart Claude Code to activate.

      To customize settings:
        #{prefix}/macos/install.sh --reconfigure

      Config: ~/.config/claude-tap/config.json
      Uninstall: #{prefix}/macos/uninstall.sh
    EOS
    unless File.exist?(File.expand_path("~/.config/claude-tap/notch-notify"))
      msg += <<~EOS

        NOTE: Notification overlay was not compiled (swiftc not found).
        Run: xcode-select --install && #{prefix}/macos/setup.sh #{prefix}
      EOS
    end
    msg
  end

  test do
    assert_predicate prefix/"macos/install.sh", :exist?
    assert_predicate prefix/"macos/setup.sh", :exist?
    assert_predicate prefix/"config.example.json", :exist?
  end
end
