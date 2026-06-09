# Homebrew cask for NetCheck.
#
# This file belongs in a SEPARATE repo named `homebrew-netcheck` (so that
# `brew tap uxvic/netcheck` resolves to github.com/uxvic/homebrew-netcheck),
# at path: Casks/netcheck.rb
#
# Users then install with:
#   brew tap uxvic/netcheck
#   brew install --cask netcheck
#
# `brew install --cask` strips the quarantine flag, so it installs WITHOUT any
# Gatekeeper warning — even though the app is unsigned. Update `version` + `sha256`
# on each release (sha256: `shasum -a 256 dist/NetCheck-<version>.dmg`).

cask "netcheck" do
  version "1.0.0"
  sha256 "REPLACE_WITH_DMG_SHA256"   # shasum -a 256 dist/NetCheck-#{version}.dmg

  url "https://github.com/uxvic/NetCheck/releases/download/v#{version}/NetCheck-#{version}.dmg"
  name "NetCheck"
  desc "Menu bar internet reachability and live throughput monitor"
  homepage "https://github.com/uxvic/NetCheck"

  livecheck do
    url "https://github.com/uxvic/NetCheck/releases/latest/download/appcast.xml"
    strategy :sparkle
  end

  auto_updates true                  # app self-updates via Sparkle
  depends_on macos: ">= :sonoma"     # macOS 14+

  app "NetCheck.app"

  zap trash: [
    "~/Library/Preferences/com.victoradedini.NetCheck.plist",
  ]
end
