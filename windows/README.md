# Foliow for Windows

A local Windows photo sorter. Open a photo folder, review a large preview, and swipe or use arrow keys to keep/pass. Undo decisions, revisit keepers or passed photos, then review and confirm recycling the passed originals. Kept files stay exactly where they are.

## Install or run

Download the Windows build artifact from the repository’s **Build Windows app** Actions run, then extract the ZIP.

- **Installer:** run `Foliow-Setup-1.0.0-x64.exe` for a per-user install; no administrator account is needed.
- **Portable:** run `Foliow-Portable-1.0.0-x64.exe`; no installation is required.

Windows 10/11, 64-bit x64. All photo decoders are included; Python, Node, RAW codecs and an internet connection are not required to use the app. The executables are unsigned, so Windows may show an unknown-publisher/SmartScreen prompt. Download only your own verified build.

## Review and delete

1. Open a folder or drop it from File Explorer. Subfolders are included. Junctions, symbolic links, hidden folders and unsupported sidecar files are skipped.
2. Swipe/drag right or press Right to keep; left or Left to pass. Ctrl+Z undoes a decision, Space skips for now, and Z toggles zoom.
3. Passing sets a label only. **Delete passed** opens the exact list of originals that will be removed.
4. Confirm the native Windows prompt to move those originals to the Recycle Bin. The app calls Windows recycling and has no permanent-delete fallback. If recycling fails, that file stays in Passed and its error is shown. Recycle support depends on the drive/provider. Restore recycled files through Windows Recycle Bin; decision Undo does not undo a completed recycling operation.

Only passed files are eligible. Before reading/recycling, the app verifies file identity, size and modification time and rejects links or paths outside the selected folder. Changed originals are skipped and must be reviewed again after reopening the folder. Keepers and unreviewed files are left in place. Start the first device check with a folder of disposable photo copies.

Decisions save to the app’s local data directory, separately for each folder. The latest folder reopens on startup. Reopen another folder to restore its earlier decisions, provided its originals have not changed. No account, upload, analytics, or network service is used.

## Formats

JPEG, PNG, WebP, AVIF, GIF, BMP, HEIC/HEIF and TIFF; camera RAW previews including CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2, PEF and more. Embedded previews are preferred, with bundled LibRaw WASM decoding as fallback. Camera/compression support varies. Unreadable or very large previews remain visible as errors and can be skipped. RAW and JPEG companions are separate entries; no companion is implicitly recycled.

## Build from source

```
npm ci
npm test
npm run check
npm start
npm run build:win
```

Run in the `windows` directory. Builds go into `windows/release`. Electron and electron-builder are pinned in the lockfile. The repository workflow builds on `windows-latest`, runs the file-safety/model/DOM tests, runs a real Electron smoke test with a disposable JPEG and native recycling, then packages NSIS and portable executables. It also smoke-tests the packaged app before publishing artifacts.

The renderer runs sandboxed with context isolation and no Node integration. The preload exposes a narrow, validated IPC bridge. It receives opaque photo IDs, not arbitrary filesystem read/delete methods. Deletion uses a short-lived review token, native confirmation, and another file check immediately before recycling.

Third-party decoder notices and source links are in `ui/THIRD_PARTY_NOTICES.md`.
