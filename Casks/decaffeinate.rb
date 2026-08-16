# Homebrew cask for Decaffeinate — this is the canonical copy; the live one lives
# in the tap repo harf-promo/homebrew-tap (Casks/decaffeinate.rb). Bump `version`
# and `sha256` together on each release (the sha is printed by
# Scripts/make-dmg.sh and published as SHA256SUMS.txt on the GitHub release).
cask "decaffeinate" do
  version "1.26.1"
  sha256 "62b7e37a3a87094f790efea12fcfbff7b6af1ab6dc244e31257e8b048fa5b638"

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

  # The in-app "Launch at login" toggle registers via SMAppService; remove the
  # login item on uninstall so no ghost entry lingers in System Settings.
  uninstall login_item: "Decaffeinate"

  zap trash: [
    "~/Library/Caches/com.harfpromo.Decaffeinate",
    "~/Library/HTTPStorages/com.harfpromo.Decaffeinate",
    "~/Library/Preferences/com.harfpromo.Decaffeinate.plist",
    "~/Library/Saved Application State/com.harfpromo.Decaffeinate.savedState",
  ]
end
