cask "eye-rest" do
  version "1.0" # Current version of your application. Update this with each new release.
  # The `.` in the version is important for cask versions (e.g., "1.0" instead of "1")

  # Replace this with the actual URL where your application's .dmg or .zip will be hosted.
  # For example, a GitHub release URL: "https://github.com/your-username/eye-rest/releases/download/v#{version}/EyeRest-#{version}.dmg"
  url "https://your-hosting-platform.com/eye-rest/EyeRest-#{version}.dmg"
  name "EyeRest" # The name of your application.
  desc "Take regular eye-rest breaks with this app." # A short description of your app.

  # Replace this with the SHA-256 checksum of your hosted file.
  # You can get this by running `shasum -a 256 /path/to/your/EyeRest-1.0.dmg` after packaging.
  sha256 "CHANGEME_SHA256_CHECKSUM"

  app "EyeRest.app" # The name of the .app bundle inside your .dmg or .zip.

  # Optionally, add a zap stanza to clean up associated files when the cask is uninstalled.
  # This helps ensure a clean uninstall for users.
  # Replace `com.yourname.EyeRest` with your actual bundle identifier.
  zap trash: [
    "~/Library/Preferences/com.yourname.EyeRest.plist",
    "~/Library/Application Support/EyeRest",
    "~/Library/Caches/com.yourname.EyeRest",
  ]

  # If your application has a bundle identifier different from the primary one,
  # or if you want to include other related identifiers, list them here.
  # For example, if your app had a helper tool with a different bundle ID.
  # If not needed, you can remove this section.
  # depends_on macos: ">= :monterey" # Minimum macOS version if applicable (e.g., Sonoma: :sonoma, Ventura: :ventura)
end
