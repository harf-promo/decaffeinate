# Homebrew cask for Decaffeinate — this is the canonical copy; the live one lives
# in the tap repo harf-promo/homebrew-tap (Casks/decaffeinate.rb). Bump `version`
# and `sha256` together on each release (the sha is printed by
# Scripts/make-dmg.sh and published as SHA256SUMS.txt on the GitHub release).
cask "decaffeinate" do
  version "1.10.1"
  sha256 "52c415478717bdefc8d5398e2df2e2d96e0fcc05af7aeeb49ff72af116a3957e"

  url "https://github.com/harf-promo/decaffeinate/releases/download/v#{version}/Decaffeinate-#{version}.dmg"
  name "Decaffeinate"
  desc "Shows what's keeping the system awake and forces a safe sleep"
  homepage "https://github.com/harf-promo/decaffeinate"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "Decaffeinate.app"

  zap trash: "~/Library/Preferences/com.harfpromo.Decaffeinate.plist"
end
