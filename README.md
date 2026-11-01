# SwipeSort

Swipe through your photos one at a time: right to keep, left to delete.
Nothing is deleted while you swipe. Photos marked for deletion go to a review
screen first, then to the Android trash in one batch, where they stay
recoverable for about 30 days.

Everything runs on the device. No server, no uploads, no paid services.

## Status

Phase 3: swiping. Open an album and swipe each photo: right to keep, left to
delete. The card tilts as you drag, a KEEP or DELETE stamp fades in, and the
phone gives a small vibration when letting go would count. A short drag
springs back; a quick flick counts even if it's short. Buttons and keys
animate the card the same way. Undo and a progress bar are always there.

Decisions are saved as you go, so you can close the app and pick up where you
stopped.

Phase 4: deleting. When you're done (or any time, from the button in the top
bar), the Review screen shows every photo marked Delete. Tap one to keep it
instead. The button at the bottom moves the rest to the trash in one go:

- Android: the system trash. Android asks once for the whole batch, then keeps
  the photos for about 30 days before removing them for good.
- Windows: a `_SwipeSort_Trash` folder inside the photo folder, keeping the
  subfolders. The app asks first. Nothing is erased.

Recently deleted (the trash-can button on the album list) shows everything
SwipeSort moved to the trash. Pick photos and restore them. On Android each
one shows how many days are left before Android removes it for good. Android
hides trashed photos even from the app that trashed them, so SwipeSort saves a
small thumbnail of each photo just before trashing it, to have something to
show. There's no "delete forever" button: the app never erases anything.

Phase 5: hardening. Tested with big libraries, older Android versions, large
text, and photos changing behind the app's back. See "Tested" below.

See the roadmap below.

On Windows: drag with the mouse, or `←` Delete, `→` Keep, `Z` (or `Ctrl+Z`,
`Backspace`) Undo.

## Tested

| What | Result |
|---|---|
| Android 11 (API 30, the minimum) | Permission, trash and restore work |
| Android 13 (API 33) | Permission and albums work |
| Android 17 (API 37) and a real Android 16 phone | Everything works |
| 10,020 photos, Android (profile build) | First photo after 0.6 s; the rest load in the background (9.6 s) |
| 10,022 photos, Windows | Album list in 1.0 s (scanned on a background isolate); opening an album 11 ms |
| 200% text size on a small phone | Every screen fits (`test/accessibility_test.dart`) |
| A marked photo deleted by another app | Dropped from the review instead of staying marked |
| Release APK size | 18 MB for most phones (arm64) |

Measure performance in a profile or release build (`flutter run --profile`),
never a debug build: debug builds are several times slower.

Android albums are pages of a stream: a small first page (200) so sorting
starts at once, then pages of 1,000. Review and Start over wait until every
page has loaded, so they always act on the whole album.

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
photos at all. It only ever deletes a folder it made itself. Add
`--many 10000` for a Bulk folder of 10,000 small photos, to test speed.

To put them on the emulator (copy the photo folders only, not a
`_SwipeSort_Trash` folder left by testing on Windows: Android would show it
as extra albums):

```bash
adb shell mkdir -p /sdcard/Pictures/SwipeSortTest
adb push E:\test-photos\Camera /sdcard/Pictures/SwipeSortTest/
adb shell content call --uri content://media --method scan_volume --arg external_primary
```

The last command makes Android index the new files, so they show up in the
gallery.

### Where decisions are saved

In a SQLite database, `decisions.db`. Table `decisions` has one row per
decided photo; table `trash` has one row per photo the app moved to the trash.
The schema is versioned (now version 2, which added `trash`), and opening an
older database upgrades it without losing anything.

- Windows: `%APPDATA%\com.photoswipe\photo_swipe\decisions.db`
- Android: the app's private storage, removed when the app is uninstalled

The Start over button in an album forgets that album's decisions. It never
touches the photos.

On Windows, SQLite comes from the `sqlite3` package's build hook, which
downloads a prebuilt `sqlite3.dll` and checks it against a SHA-256 hash
stored in the package.

### Platform differences

- HEIC photos: Android shows them; the Windows build skips them, because
  Windows can't decode HEIC, and says so on the album list.
- File size isn't shown on Android yet.
- `android/gradle.properties` turns off Kotlin incremental compilation. The
  project is on drive E: and Flutter's package cache is on C:, and the
  incremental compiler can't handle paths across drives.

### Known risks

- photo_manager 3.12 still applies the Kotlin Gradle Plugin. Flutter warns
  that future versions will refuse to build such plugins, so photo_manager
  will need updating once it supports Flutter's built-in Kotlin.

## Project structure

```
lib/
├── main.dart     App entry point
├── models/       Plain data classes: Photo, Album, Decision
├── data/         Where photos and decisions come from (repositories, SQLite)
├── state/        App logic the screens listen to (current photo, undo, progress)
├── screens/      Full pages: album picker, swipe, review, done
└── widgets/      Reusable pieces: swipe card, photo card, buttons, progress bar
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
- [x] Phase 3: swipe gestures and animations
- [x] Phase 4: review screen and batch delete to the Android trash
- [x] Phase 5: edge cases, tests, hardening
- [ ] Phase 6: UI and animation polish (beta feedback: the current look is
      plain; this phase gives it a real visual design)
- [ ] Phase 7: release APK

## Safety rules

- The app never deletes a photo during swiping. It only records a decision.
- Deletion happens only after the review screen, as a move to the system trash.
  The app never erases a file itself.
- A decision is forgotten only after its photo has really been moved, so a
  crash part-way can't lose track of a photo.
- The Windows build refuses to move any file outside its photo folder.
- Develop against `test-photos/`, never a real photo library. That folder is
  git-ignored, because photos are personal data.
