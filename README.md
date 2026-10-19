# Foliow — iPhone and Windows

The native Windows desktop app is in [`windows/`](windows/README.md). Its separate **Build Windows app** workflow produces an installer and portable executable with bundled RAW decoders and confirmed recycling of passed originals.

## iPhone app

Native SwiftUI photo review for iOS 17 or later. Swipe right to keep and left to pass. Undo before deleting. When you finish, review a list of passed photos and explicitly confirm deletion of those originals. Keepers stay where they were; there is no keeper-download step.

## Download and install on Windows

The first iPhone build is ready: [download Foliow-unsigned.ipa](https://foliow-photo-sorter.indigoridge.chatgpt.site/downloads/Foliow-unsigned.ipa). Requires iOS 17 or later. [Successful hosted build and artifacts](https://github.com/PainBurger100/Camera-save/actions/runs/38905741338).

1. Install [Sideloadly](https://sideloadly.io) on Windows and follow its Apple-driver requirements.
2. Connect and unlock your iPhone, then trust the computer.
3. Select the IPA in Sideloadly, sign with your own Apple ID, and install it. [AltStore Classic](https://altstore.io) is an alternative signing tool.
4. Enable Developer Mode and trust the developer profile in iPhone Settings if prompted. Free Apple signing generally needs renewal every seven days.

The downloadable IPA is unsigned. The GitHub build compiled successfully and all seven deletion-safety tests passed in an iPhone simulator. Actual device installation and photo-provider behavior still need testing on your iPhone. For the first device check, use a folder of disposable photo copies.

## Rebuild from Windows without owning a Mac

This download is the complete source project, not an IPA. A hosted Mac must compile it once. The included GitHub Actions workflow does that without requesting Apple signing credentials. GitHub-hosted macOS runners may require Actions minutes or billing depending on your account and repository settings.

1. Install GitHub Desktop from https://desktop.github.com and sign in to your GitHub account.
2. Create a new repository named `foliow-iphone` in GitHub Desktop. Open its local folder in Explorer.
3. Extract this ZIP. Copy its **contents** into that repository folder: `Foliow.xcodeproj`, `Foliow`, `FoliowTests`, `.github`, and the other files. Do not nest everything inside another `Foliow-iPhone` directory. In GitHub Desktop, commit the files, then publish the repository. Keep it private if you prefer.
4. Open the repository on GitHub. Select **Actions → Build iPhone IPA**. A push to `main` or `master` runs it automatically; you can also use **Run workflow**.
5. Wait for a successful run. It runs deletion-safety XCTest cases in an iPhone simulator, builds for a physical iPhone, and uploads the **Foliow-iPhone** artifact. If the run fails, open the failed step to see the compiler/test error; no installable artifact is published on a failed build.
6. Download the artifact ZIP on Windows and extract **Foliow-unsigned.ipa**. This binary still needs to be signed for your device.
7. Install Sideloadly from its official site, https://sideloadly.io. Follow its current Windows Apple-driver requirements. Connect your iPhone by USB, unlock it, and trust the computer.
8. In Sideloadly, select the IPA and your connected iPhone. Sign with your own Apple ID using the tool’s interface, then install. Do not send Apple ID passwords or signing keys in chat. AltStore Classic from https://altstore.io is another Windows option that can sign and install your own IPA.
9. If iOS requests it, enable **Developer Mode** in Settings → Privacy & Security and restart. Trust the developer profile under Settings → General → VPN & Device Management if required.

Free Apple developer signing generally expires after seven days; renew it using your signing tool. Keep the same signing account and bundle identifier when refreshing to preserve the app’s saved session. Reinstalling/removing the app can erase its saved decisions.

## Using the app

- **Files:** choose an existing folder in the Files picker. The app opens that location in place, including subfolders. Download cloud folders locally in Files before review. External drives and providers must allow access and deletion. Nothing is copied into a separate import library.
- **Photos:** grant read/write access and choose an album or all accessible photos. With limited access, only permitted photos are visible. Use Settings → Apps → Foliow → Photos to grant more access if needed.
- Swipe or tap **Keep**/**Pass**. Pass only sets a label. Use Undo to change decisions, or revisit the Keepers and Passed tabs.
- Tap **Review & delete passed**. Read the exact file list, then confirm deletion. Photos displays Apple’s own deletion prompt as well.
- A Files deletion removes the actual original from the selected folder. Recovery depends on the file provider and is not guaranteed. Photos deletions normally go to Recently Deleted for 30 days and sync across iCloud Photos devices. The app cannot undo physical deletion.
- Files changed since review are skipped during deletion. Errors remain listed as Passed. Keepers and unreviewed photos are never included in deletion requests.
- CR2 and other camera RAW formats use native ImageIO and Quick Look previews. Camera/compression support depends on the installed iOS version. HEIC, JPEG, PNG, TIFF and other iOS-supported image formats work through the same preview path. A failed preview is shown explicitly and can be skipped.
- RAW and JPEG companions in Files are independent entries. In Photos, a RAW+JPEG or Live Photo is one library asset; deleting that asset removes all its associated resources.
- The current session and decisions save on the iPhone. Folder access is restored using the iOS security-scoped bookmark; reselect the original folder if iOS or the provider revokes it. Opening another source replaces the current saved session. Photos never upload to an app server; iCloud Photos can download previews through Apple’s APIs.

## Optional: install using Xcode on a Mac

Open `Foliow.xcodeproj`, select the Foliow target → Signing & Capabilities, choose your development team and a unique bundle identifier, connect the iPhone, then Run. No third-party packages or API keys are required.

## Verification and build status

- Xcode 16.4 simulator build and device Release build: passed.
- Seven deletion-safety XCTest cases: passed, zero failures.
- IPA inspected: arm64 device binary, iOS 17 minimum, correct Payload/Foliow.app structure, no test bundle.
- Built source commit: `260e4c65dc2fbb87ad2990f29d746ace9c8fb409`.
- Build: https://github.com/PainBurger100/Camera-save/actions/runs/38905741338
- IPA SHA-256: `1d140fe6fdeb426ebb35e771eaa71bcc64b00f23c89cb14a6c913e0b2164c52c`.
- Apple ID signing, installation and testing on a physical iPhone remain required.

The XCTest cases verify that deletion removes only passed originals, protects keepers and unreviewed files, refuses changed originals and path traversal, excludes symlinks, and restores decisions only for unchanged files. No personal photos were used for these tests.
