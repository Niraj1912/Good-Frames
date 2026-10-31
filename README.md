# SwipeSort

Swipe through your photos one at a time: right to keep, left to delete.
Nothing is deleted while you swipe. Photos marked for deletion go to a review
screen first, then to the Android trash in one batch, where they stay
recoverable for about 30 days.

Everything runs on the device. No server, no uploads, no paid services.

## Status

Phase 2: decisions. Open an album and mark each photo Keep or Delete, with
undo and a progress bar. Decisions are saved as you go, so you can close the
app and pick up where you stopped. Nothing is deleted yet. See the roadmap
below.

On Windows: `←` Delete, `→` Keep, `Z` (or `Ctrl+Z`, `Backspace`) Undo.

## Supported platforms

| Platform | Purpose | Minimum version |
|---|---|---|
| Android | The real app, sorting the phone's gallery | Android 11 (API 30), the first version with the MediaStore trash |
| Windows | Fast development and testing, sorting a folder of test photos | Windows 10 |

## Running it

Needs Flutter (see `flutter doctor`), plus Android Studio for Android builds
and Visual Studio's "Desktop development with C++" for Windows builds.

```bash
flutter pub get
dart run tool/make_test_photos.dart   # makes E:\test-photos (once)
flutter run -d windows                # fastest for day-to-day work
flutter run -d emulator-5554          # Android emulator
flutter test                          # automated tests
```

While `flutter run` is running, press `r` to hot reload and `q` to quit.

The Windows build reads `E:\test-photos`. To use another folder, add
`--dart-define=PHOTO_ROOT=D:\other\folder` to `flutter run`.

### Test photos

`tool/make_test_photos.dart` makes a folder of deliberately awkward files:
portrait and landscape photos, a 24-megapixel photo, one stored sideways with
an EXIF rotation tag, the same file name in two folders, a folder name with a
space, a corrupt file, an empty file, a HEIC file, and files that aren't
photos at all. It only ever deletes a folder it made itself.

To put them on the emulator:

```bash
adb push E:\test-photos /sdcard/Pictures/SwipeSortTest
adb shell content call --uri content://media --method scan_volume --arg external_primary
```

The second command makes Android index the new files, so they show up in the
gallery.

### Where decisions are saved

In a SQLite database, `decisions.db`, with one row per decided photo:

- Windows: `%APPDATA%\com.photoswipe\photo_swipe\decisions.db`
- Android: the app's private storage, removed when the app is uninstalled

The Start over button in an album forgets that album's decisions. It never
touches the photos.

On Windows, SQLite comes from the `sqlite3` package's build hook, which
downloads a prebuilt `sqlite3.dll` and checks it against a SHA-256 hash
stored in the package.

### Platform differences

- HEIC photos: Android shows them; the Windows build skips them, because
  Windows can't decode HEIC.
- File size isn't shown on Android yet.
- `android/gradle.properties` turns off Kotlin incremental compilation. The
  project is on drive E: and Flutter's package cache is on C:, and the
  incremental compiler can't handle paths across drives.

## Project structure

```
lib/
├── main.dart     App entry point
├── models/       Plain data classes: Photo, Album, Decision
├── data/         Where photos and decisions come from (repositories, SQLite)
├── state/        App logic the screens listen to (current photo, undo, progress)
├── screens/      Full pages: album picker, swipe, review, done
└── widgets/      Reusable pieces: swipe card, action buttons, progress bar
test/             Automated tests (test/fakes/ holds FakePhotoRepository)
tool/             Developer scripts, such as the test-photo generator
android/          Android project (permissions live in AndroidManifest.xml)
windows/          Windows project
```

The screens never talk to the gallery directly. They use a `PhotoRepository`
interface, which has one implementation per environment:

- `FakePhotoRepository`: in-memory photos for automated tests
- `FolderPhotoRepository`: reads a test folder, for the Windows build
- `AndroidPhotoRepository`: the phone's gallery, via MediaStore

## Roadmap

- [x] Phase 0: setup
- [x] Phase 1: read-only viewer (permissions, albums, next/previous)
- [x] Phase 2: keep/delete decisions saved in SQLite, resume, undo
- [ ] Phase 3: swipe gestures and animations
- [ ] Phase 4: review screen and batch delete to the Android trash
- [ ] Phase 5: edge cases, tests, hardening
- [ ] Phase 6: release APK

## Safety rules

- The app never deletes a photo during swiping. It only records a decision.
- Deletion happens only after the review screen, as a move to the system trash.
- Develop against `test-photos/`, never a real photo library. That folder is
  git-ignored, because photos are personal data.
