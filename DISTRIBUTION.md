# ZappDesk direct distribution

ZappDesk ships outside the Mac App Store and updates itself with Sparkle 2. Releases are
hosted on GitHub Releases. The app reads its appcast from the stable "latest release" URL:

`https://github.com/vzandli/ZappDesk/releases/latest/download/appcast.xml`

That URL always redirects to the `appcast.xml` asset attached to the newest published
release, so every release must carry a fresh `appcast.xml`. `scripts/release.sh` handles this.
If the repository moves, update `SUFeedURL` in `Configuration/Info.plist` and `ZAPPDESK_REPO`
in the script.

## One-time setup

- The project uses Xcode project format 77, which opens in both Xcode 26.6 and Xcode 27.
  Do not let Xcode 27 upgrade it to format 110, or Xcode 26 will refuse to open it.
- The deployment target is macOS 14.0.
- The GitHub repository must be public. Sparkle downloads anonymously, and assets on
  private repositories require authentication.
- Install the GitHub CLI and sign in: `gh auth login`.
- Keep the Sparkle private key in the login Keychain under the `ZappDesk` account
  (created with `generate_keys --account ZappDesk`). Never commit, export, or upload the
  private key. The matching public key is `SUPublicEDKey` in `Configuration/Info.plist`.
- Sign with a Developer ID Application certificate and keep Hardened Runtime enabled.
  Sparkle's tools live in Xcode's SwiftPM artifacts, for example
  `~/Library/Developer/Xcode/DerivedData/ZappDesk-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`.

## Publish a release

1. Increment both `MARKETING_VERSION` (the visible version) and `CURRENT_PROJECT_VERSION`
   (the build number) in Xcode. Sparkle orders updates by the build number, so it must
   always increase.
2. Archive the Release build.
3. In Organizer, choose **Distribute App → Direct Distribution** to sign with Developer ID
   and notarize. Export the notarized `ZappDesk.app`.

   Or from the command line:

   ```sh
   xcodebuild -project ZappDesk.xcodeproj -scheme ZappDesk -configuration Release \
     -archivePath releases/ZappDesk.xcarchive archive
   xcodebuild -exportArchive -archivePath releases/ZappDesk.xcarchive \
     -exportOptionsPlist releases/ExportOptions.plist -exportPath releases/export
   ditto -c -k --keepParent releases/export/ZappDesk.app releases/ZappDesk-notarize.zip
   xcrun notarytool submit releases/ZappDesk-notarize.zip --keychain-profile GaugeZ --wait
   rm releases/ZappDesk-notarize.zip
   ```

   `ExportOptions.plist` uses `method` = `developer-id`, `teamID` = `8FKL69633T`,
   `signingStyle` = `automatic`, `destination` = `export`. The `GaugeZ` keychain profile
   holds the notarization credentials shared by all ZYORK apps; it was created once with
   `xcrun notarytool store-credentials GaugeZ --apple-id … --team-id 8FKL69633T`.
   Delete the notarization zip afterwards: `generate_appcast` treats every zip in
   `releases/` as a release archive and fails when two carry the same version.
4. Staple the notarization ticket to the exported app. The release script refuses to
   continue without it:

   ```sh
   xcrun stapler staple /path/to/ZappDesk.app
   ```

5. Optionally write release notes in Markdown, saved outside `releases/`. They are
   embedded in the appcast and used as the GitHub release description.
6. Run the release script:

   ```sh
   scripts/release.sh /path/to/ZappDesk.app notes.md
   ```

   The script verifies the signature and staple, zips the app with `ditto` so framework
   symlinks survive, downloads the last three release archives and the current appcast so
   history and delta updates are preserved, signs the new entry with the Keychain key,
   and creates the `vX.Y.Z` GitHub release with the archive, deltas, and `appcast.xml`.
7. Open the release on GitHub and confirm `appcast.xml`, the zip, and any `.delta` files
   are attached. Then run **Check for Updates…** from the previous public ZappDesk build.

Work files land in `releases/`, which is ignored by git.

## Notes and caveats

- Never mark a release as a draft or pre-release. The `latest/download` URL skips both,
  so Sparkle would keep serving the previous appcast.
- Do not delete old release archives. Delta updates for the next version are built
  against them, and the appcast keeps entries for them.
- Regenerate the appcast only after the archive is signed, notarized, and stapled.
  Changing the app afterwards invalidates the EdDSA signature.
- ZappDesk runs as a menu bar app. Scheduled update checks that find a new version while
  the app is in the background are shown as "Update to X Available…" in the status menu
  and in Settings → About instead of an alert. When the menu bar icon is hidden, Sparkle's
  standard alert is used instead.
- ZappDesk needs Accessibility permission. That permission is tied to the code signature's
  designated requirement, so a Developer ID signed update keeps it; a differently signed
  build must be granted again.
