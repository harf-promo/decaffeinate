# Homebrew cask for Decaffeinate — this is the canonical copy; the live one lives
# in the tap repo harf-promo/homebrew-tap (Casks/decaffeinate.rb). Bump `version`
# and `sha256` together on each release (the sha is printed by
# Scripts/make-dmg.sh and published as SHA256SUMS.txt on the GitHub release).
cask "decaffeinate" do
  version "1.5.0"
  sha256 "24e1ff76cd0323ba4ae2cf683f5c8702523752a65d1bdaad3e5b6c198e573346"

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
