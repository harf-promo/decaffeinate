# Homebrew cask for Decaffeinate — this is the canonical copy; the live one lives
# in the tap repo harf-promo/homebrew-tap (Casks/decaffeinate.rb). Bump `version`
# and `sha256` together on each release (the sha is printed by
# Scripts/make-dmg.sh and published as SHA256SUMS.txt on the GitHub release).
cask "decaffeinate" do
  version "1.4.1"
  sha256 "5c5075f61fa3fb14b237e6e643008ee4a300e3b14fcc789918ede31120c33dbf"

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
