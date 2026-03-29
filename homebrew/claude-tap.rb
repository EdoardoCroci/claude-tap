class ClaudeNotifier < Formula
  desc "Dynamic Island-style notifications, sound alerts, and status line for Claude Code"
  homepage "https://github.com/EdoardoCroci/claude-tap"
  url "https://github.com/EdoardoCroci/claude-tap.git", branch: "main"
  version "1.1.0"
  license "MIT"

  depends_on :macos
  depends_on "jq" => :recommended

  def install
    prefix.install Dir["*"]
  end

  def caveats
    <<~EOS
      Run the installer to configure:
        #{prefix}/macos/install.sh

      Or reconfigure:
        #{prefix}/macos/install.sh --reconfigure

      To uninstall hooks and config:
        #{prefix}/macos/uninstall.sh
    EOS
  end
end
