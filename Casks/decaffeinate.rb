# Homebrew cask for Decaffeinate.
#
# For a personal tap (harf-promo/homebrew-tap), copy this file into that repo's
# Casks/ directory. `sha256 :no_check` lets it track releases without per-release
# edits; submitting to homebrew/cask core later requires a real sha256 (it's
# printed by Scripts/make-dmg.sh and published as SHA256SUMS.txt on each release).
cask "decaffeinate" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/harf-promo/decaffeinate/releases/download/v#{version}/Decaffeinate-#{version}.dmg"
  name "Decaffeinate"
  desc "Makes your Mac sleep — sees what's keeping it awake and forces a safe sleep"
  homepage "https://github.com/harf-promo/decaffeinate"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Decaffeinate.app"

  zap trash: [
    "~/Library/Preferences/com.harfpromo.Decaffeinate.plist",
  ]
end
