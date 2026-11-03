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

Not sure about a photo? Swipe it up (or tap the clock button) to decide
later. It goes to the back of the line and comes back once everything else
in the album is sorted; a blue "Later" count shows how many are waiting.
Undo brings it straight back. Putting off is only for that visit: it isn't
saved, so if you leave the album, the photo is simply unsorted in its usual
place next time.

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
from lookups), so the app does it with its own Android code (below).

Folder mode: on first launch, Android users choose what SwipeSort sees:

- **Choose a folder**: Android's folder picker. SwipeSort then sees that
  folder and the folders inside it, and nothing else; each folder holding
  photos is an album. No photo permission is involved at all: picking the
  folder is the permission (the Storage Access Framework). Android's own
  photo prompt can't do this: it offers every photo, or photos picked one
  by one.
- **All photos, or some**: Android's photo permission, as before. On
  Android 14+ its prompt also offers "Allow limited access", for picking
  photos one by one. The app can't open that picker directly, so the card
  says "or some" to show the way to it.

Folders can be added or removed later (Folders, on the album list), and
either mode can switch to the other. Both identify photos by Android's
gallery id, so decisions, the trash and Recently deleted carry over. A photo
Android hasn't indexed yet can't be trashed, so it's left out, and the
album list says how many.

The app's own Android code, in `android/app/src/main/kotlin/`, covers what
photo_manager can't: `TrashRequests.kt` (trash, restore and delete-forever
prompts, by gallery id, used in both modes) and `FolderAccess.kt` (the
folder picker, scanning chosen folders, decoding their photos at screen
size), plus the app's version for Settings, answered in `MainActivity.kt`.
Dart reaches them through platform channels (`lib/data/android_media.dart`
and `lib/data/app_info.dart`).

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

Settings (the gear on the album list). Kept short on purpose: every setting
is a question the user has to answer, so only things people really disagree
about are there.

- **Swipe directions**: right keeps (the default), or the other way round.
  The Keep and Delete buttons, the KEEP/DELETE stamps and the arrow keys all
  follow, so the button is always on the side the card flies to.
- **Order**: newest first (the default) or oldest first.
- **Vibration**: the small buzz when letting go will count. On by default.
- **Theme**: the same as the phone (the default), light, or dark. It
  changes at once.
- **What SwipeSort sees** (Android): all photos, the photos picked one by
  one, or the shared folders. Tapping it opens the Folders screen, or the
  first-launch choice with a Cancel button.
- **About**: the version, read from Android so it always matches the
  installed APK (`1.0.0 (1)`: the name, then the number Android compares),
  and the open-source licences of every package the app is built from.
  Those packages are free on the condition that their notices go with the
  app; Flutter's built-in licence page lists them all.

Settings are saved in the same database as decisions. Nothing in Settings
can weaken a safety rule: Delete forever always warns, and Android's own
prompts can't be turned off anyway.

All-photos mode used to show photos in the order Android added them to its
database (roughly oldest first), because the app never asked for an order;
the album covers were the oldest photos too. Since Settings, the app always
asks Android for newest or oldest first by date added, with the photo's id
breaking ties: photos copied in together share the same second, and paging
needs an order that's the same on every page, or a photo could be skipped.

## Design

All of it lives in `lib/theme/` (design tokens: colours, type, shapes, in
`app_theme.dart`), so screens never pick their own colours.

- Photo first: the app's own surfaces are neutral (near-black in dark
  mode, warm off-white in light), and the photo being sorted is a card of
  its own shape: as large as fits, never cropped, with rounded corners and
  no frame or bars around it, like a print. Cropping to fill would hide
  the edges of a photo you're deciding to delete, and a blurred fill would
  put noise next to it. The whole area still catches drags, so a thin
  panorama is as easy to swipe as a tall portrait. The next photo waits
  behind out of sight, so a bigger one never shows round the edges of a
  smaller one; as you drag, it fades in and grows to full size, ready to
  take the front. A file that can't be shown gets a dark 3:4 card with a
  message.
- Album colours come from the photos: each album's name sits on a panel
  tinted from its cover (`photo_tint.dart`), so that colour belongs to the
  pictures and never competes with them. A 32-pixel copy of the cover is
  grouped into at most 32 colours, and the one with the best mix of how
  much of the photo it covers and how colourful it is wins, off the main
  thread. It's Material's colour science (HCT: hue, chroma, tone), the
  same that picks Android's colours from the wallpaper. The panel keeps
  the cover's hue but sets its own tone (lightness), and tone decides
  contrast, so text stays readable on any cover's tint; a test checks
  every hue in both modes. A grey cover gets a plain panel.
  (Tinting the whole sorting screen with each photo's colour was tried
  and dropped: it changed with every swipe and pulled attention from the
  photo.)
- Colour carries meaning: green keeps, brick red deletes (`SortColors`, a
  theme extension), and one ink-blue accent marks other actions and
  choices. The meaning colours show up as colour blocks where they help:
  the counts above the photo sit on small green and red tiles with the
  same icons as the buttons, the end of an album shows the two totals on
  big green and red tiles, the progress bar is split green and red, the
  Delete button is tinted red, and the Review screen's note is red.
  Settings' icons sit on soft tiles of the accent blue. Everything else is
  ink on paper.
- While you drag, the buttons show what letting go will do instead of the
  photo being coloured: the button the photo is heading for grows with
  the drag, and Delete turns solid red once letting go would delete (the
  moment the phone vibrates). It switches with a short fade rather than
  shading in along the way, so its label never blends into the red. (A
  green or red wash behind the card was tried and dropped: around a
  photo-shaped card it became a coloured box that pulled attention from
  the photo.)
- Quiet shapes: 12-16 px corners and hairline borders instead of shadows or
  glows. No gradients, no decorative blur, no emoji in the interface.
- Numbers use tabular figures (so counters don't wobble) and thousands
  separators ("10,020").
- Motion explains something: a flicked card leaves at the flick's speed, a
  short drag springs back with a real spring, and an undone photo slides back
  in from the side it left on (from the top if it was put off for later). A
  drag counts in whichever direction it moved furthest, and the stamp and
  buttons only ever show that one, so they always say what letting go will
  do. Nothing moves just to decorate.
- Albums are shown by their newest photo, not a generic icon.
- Light and dark mode follow the phone's setting, unless the user picks one
  in Settings.

See the roadmap below.

On Windows: drag with the mouse, or `←` Delete, `→` Keep, `↑` Later, `Z` (or
`Ctrl+Z`, `Backspace`) Undo. Click the photo to zoom; in the viewer the arrows still
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
| Folder mode, Android 11 and 17 emulators, no photo permission | Choose, sort, zoom (rotation right), trash, restore, delete forever; decisions carried over from all-photos mode |
| Signed 1.0.0 release on a real Android 16 phone | Installs; signed with the release key, not debuggable |
| Settings, Android 17 emulator | Swapped directions (buttons, stamps), oldest and newest first, dark theme at once, version from Android, licences page, choice screen's Cancel and back gesture; all remembered after a restart |
| Signed 1.0.1 installed over 1.0.0, Android 17 emulator | Updates in place: decisions, Recently deleted and photo access kept; Settings, folder mode and restore work in the release build |
| Upgrading 1.0.0's database (version 2) | Decisions and Recently deleted kept on the emulator, and in `test/decision_store_test.dart` |

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

   Or `flutter build apk --release` for one universal APK (51 MB) that runs
   on any phone. Stick with one kind for each phone: split APKs add 1,000 ×
   the processor's number to the build number (arm64's is 2), so after an
   arm64 APK, a universal one counts as older and Android refuses it.

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
decided photo; table `trash` has one row per photo the app moved to the trash;
table `settings` has one row per setting the user changed (name and value, as
text). The schema is versioned (now version 3: version 2 added `trash`, and
version 3 `settings`), and opening an older database upgrades it without
losing anything.

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
- File size isn't shown on Android in all-photos mode (folder mode shows it).
- Testing tip: a photo copied to an Android 11 emulator with `adb push` can
  stay marked "pending" (half-written), which hides it from every app. Clear
  it with `adb shell content update --uri
  content://media/external/images/media/<id> --bind is_pending:i:0`.
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
├── models/       Plain data classes: Photo, Album, Decision, PhotoOrder, KeepSide
├── data/         Where photos and decisions come from (repositories, SQLite)
├── state/        App logic the screens listen to (current photo, undo,
│                 progress, settings)
├── screens/      Full pages: album picker, swipe, review, done, settings
├── theme/        Design tokens: colours, type, shapes (app_theme.dart), and
│                 the tint borrowed from photos (photo_tint.dart)
└── widgets/      Reusable pieces: swipe card, photo card, buttons, progress
                  bar, note card
test/             Automated tests (test/fakes/ holds FakePhotoRepository)
tool/             Developer scripts, such as the test-photo generator
android/          Android project (permissions live in AndroidManifest.xml;
                  the app's own Kotlin code in app/src/main/kotlin/)
windows/          Windows project
```

The screens never talk to the gallery directly. They use a `PhotoRepository`
interface, which has one implementation per environment:

- `FakePhotoRepository`: in-memory photos for automated tests
- `FolderPhotoRepository`: reads a test folder, for the Windows build
- `AndroidPhotoRepository`: the phone's whole gallery, via MediaStore
- `AndroidFolderPhotoRepository`: only folders the user chose (folder mode)

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
- [x] More colour: album panels tinted from their covers, keep/delete tiles,
      a dark photo card, grouped Settings
- [x] Phase 7: release: app icon, splash screen, signed release APK
- [x] Delete forever from Recently deleted
- [x] Folder mode: share chosen folders instead of every photo
- [x] Settings: swipe directions, order, vibration, theme, what SwipeSort
      sees, version and licences
- [x] Decide later: swipe up to put a photo off until the rest are sorted

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
- In folder mode the app can only read the folders the user picked, and
  every trash, restore or erase still goes through Android's own prompt.
- Develop against `test-photos/`, never a real photo library. That folder is
  git-ignored, because photos are personal data.
