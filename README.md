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
  subfolders. The app asks first. Nothing is erased yet.

Recently deleted (the trash-can button on the album list) shows everything
SwipeSort moved to the trash. Pick photos and restore them, or delete them
forever to free the space now instead of waiting. On Android each one shows
how many days are left before Android removes it for good. Android hides
trashed photos even from the app that trashed them, so SwipeSort saves a
small thumbnail of each photo just before trashing it, to have something to
show.

Delete forever is the only thing in the app that can't be undone, so it's
fenced in: it only works on photos already in the trash, only on the ones
you tick, and only after a warning in plain words. On Android, Android then
asks again with its own prompt showing the photos. photo_manager can't erase
trashed photos (it looks each one up first, and Android hides trashed photos
from lookups), so this is the app's one piece of its own Android code:
`MainActivity.kt`, reached from Dart through a platform channel.

Phase 5: hardening. Tested with big libraries, older Android versions, large
text, and photos changing behind the app's back. See "Tested" below.

Phase 6: design. A restrained, photo-first look; see "Design" below.

Checking a photo up close: tap the card (instead of swiping) and the photo
grows into a full-screen viewer on black. Pinch to zoom, drag to look around,
or double-tap to jump to 100% (one photo pixel per screen pixel, the honest
way to judge sharpness); double-tap again to fit. It shows the date, file size
and real pixel size. Keep or Delete right there, and the card flies off the
same way a swipe would; the close button goes back without deciding.

The viewer loads a bigger copy of the photo (up to 4,096 px on the long side)
than the card uses, showing the card's copy until it's ready, and frees it as
soon as the viewer closes, so a 50-megapixel photo never sits in memory.

## Design

All of it lives in `lib/theme/app_theme.dart` (design tokens: colours, type,
shapes), so screens never pick their own colours.

- Photo first: neutral surfaces (near-black in dark mode, warm off-white in
  light), not tinted, so photos' own colours read true.
- Colour carries meaning: green keeps, brick red deletes (`SortColors`, a
  theme extension), and one ink-blue accent marks other actions and
  selections. The meaning colours show up where they help: the progress bar
  is split green and red, the counts are coloured, the Delete button is
  tinted red, and the space behind the card washes green or red as you drag.
  Everything else is ink on paper.
- Quiet shapes: 12-16 px corners and hairline borders instead of shadows or
  glows. No gradients, no decorative blur, no emoji in the interface.
- Numbers use tabular figures (so counters don't wobble) and thousands
  separators ("10,020").
- Motion explains something: a flicked card leaves at the flick's speed, a
  short drag springs back with a real spring, and an undone photo slides back
  in from the side it left on. Nothing moves just to decorate.
- Albums are shown by their newest photo, not a generic icon.
- Light and dark mode both follow the phone's setting.

See the roadmap below.

On Windows: drag with the mouse, or `←` Delete, `→` Keep, `Z` (or `Ctrl+Z`,
`Backspace`) Undo. Click the photo to zoom; in the viewer the arrows still
decide and `Esc` closes.

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
| App icon and splash screen | Right on Android 11 and 17, light and dark mode |
| Release APK permissions | Photo access only; no internet |
| Delete forever, Android 17 emulator | Android's own prompt appears for trashed photos; Deny keeps them, Allow erases them |
| Signed 1.0.0 release on a real Android 16 phone | Installs; signed with the release key, not debuggable |

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

### Building a release APK

Android only installs signed apps, and only lets an update replace an
installed app if both are signed with the same key. So the key is the app's
identity: make it once, keep it forever, and back it up (a password manager
or a USB stick). Lose it and phones can't update to your next version
without uninstalling first, which wipes the app's saved decisions.

1. Make the key (once). From the project folder in PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -File tool\make_release_key.ps1
   ```

   It asks for your name and a password, then makes two files: the key,
   `%USERPROFILE%\keys\swipesort-release.jks` (outside the project, so it
   can't be committed), and `android\key.properties`, which tells the build
   where the key is and its password (git ignores it). It never replaces an
   existing key. `-ExecutionPolicy Bypass` lets this one script run without
   changing Windows' setting that blocks scripts in general.
   (To do it by hand instead, see `android/key.properties.example`.)
2. Back up the `.jks` file and the password.
3. Build. `--split-per-abi` makes one smaller APK per processor type; most
   phones want `app-arm64-v8a-release.apk` (18 MB):

   ```bash
   flutter build apk --release --split-per-abi
   ```

Without `android/key.properties`, release builds still work but are signed
with Flutter's shared debug key, which is fine for testing and not for
sharing.

The release APK asks only for photo access. Unlike debug builds, which need
internet access to talk to the laptop's debugger, it has no internet
permission, so Android itself guarantees photos can't leave the phone.

Publishing on Google Play costs a one-time US$25, so for now the APK is
shared directly (or from a free GitHub release). Installing it means
allowing "Install unknown apps" for whichever app opens the file.

The version is `version:` in `pubspec.yaml`: `1.0.0+1` means version name
1.0.0 (what people see) and build number 1 (what Android compares; it must go
up with every APK you share). The app ID `com.photoswipe.photo_swipe` is
permanent: change it and Android treats it as a different app.

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
├── theme/        Design tokens: colours, type, shapes (app_theme.dart)
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
- [x] Phase 6: UI and animation polish (beta feedback: the look was plain,
      and must not look "vibe coded")
- [x] Zoom to check a photo before deciding, and more meaningful colour
- [x] Phase 7: release: app icon, splash screen, signed release APK
- [x] Delete forever from Recently deleted

## Safety rules

- The app never deletes a photo during swiping. It only records a decision.
- Deletion happens only after the review screen, as a move to the system trash.
- A photo is erased for good only from Recently deleted: one already in the
  trash, that you ticked, after a warning (and on Android, Android's own
  prompt too). Nothing else in the app can erase a file.
- The Windows build only ever erases files inside its own trash folder, never
  one still in the library, whatever its database says (there's a test that
  tries).
- A decision is forgotten only after its photo has really been moved, so a
  crash part-way can't lose track of a photo.
- The Windows build refuses to move any file outside its photo folder.
- Develop against `test-photos/`, never a real photo library. That folder is
  git-ignored, because photos are personal data.
