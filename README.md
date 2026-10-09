# Stroke Counter

A golf stroke counter: log every stroke of a round with its club, modifiers and GPS position, then see distances,
gross, net and Stableford on the scorecard. It runs as a web app on the phone's home screen, as an iOS app, and
as an Apple Watch app that logs strokes from the wrist.

## How the parts fit together

| Folder | What it is | Built with |
| --- | --- | --- |
| `web/` | The whole app: data, rules and every screen, in one file (`index.html`) | Plain HTML, CSS and JavaScript, no build step |
| `ios/` | iOS app: a WKWebView around `web/index.html`, plus native bridges | SwiftUI, generated with xcodegen |
| `watch/` | Apple Watch app for logging strokes during a round | SwiftUI, native |

The web app owns all data. In the iOS app it runs inside the web view and stores everything in that web view's
`localStorage`. The native bridges only relay:

- **GPS** (`GPSBridge.swift`, `gps-shim.js`): replaces `navigator.geolocation` with CoreLocation inside the app.
- **Course map** (`CourseMapBridge.swift`, `CourseMapViewController.swift`): a native MapKit satellite map of the hole.
- **Scorecard scan** (`ScorecardBridge.swift`, `ScorecardReader.swift`): on a new course, photographs a printed
  scorecard with the document camera and reads its text with Vision on the phone (offline, nothing uploaded). The web
  app's `parseScorecard()` finds holes, par, index and lengths in the words and fills the course editor.
- **Watch sync** (`WatchBridge.swift`): passes the round to the watch and the watch's strokes back to the web app.
- **Dialogs** (`WebAppView.swift`): shows the web app's `confirm()` and `alert()`, which WKWebView otherwise ignores.

Each bridge is feature-detected in `index.html`, so the same file also works in a normal browser, where the
bridges simply don't exist.

## Web app

### Run locally

Serve the folder over HTTP, since GPS needs `http://localhost` or HTTPS:

```sh
cd web && python3 -m http.server 8000
# open http://localhost:8000
```

### Deploy

Every push to `main` that touches `web/` runs `.github/workflows/pages.yml`, which publishes `web/` to GitHub
Pages at <https://henrikdav.github.io/Strokecounter/>. The Pages source in the repo settings must be
"GitHub Actions".

GitHub sometimes cancels the deploy job while it is still queued (it shows as failed with no steps run). Start it
again with:

```sh
gh run rerun <run id>      # gh run list --limit 1 shows the id
```

On the phone, pull down on a screen to reload, or tap the "new version" banner. The app finds updates by
comparing `index.html` with the server's copy, so everything the app needs must stay in that one file.

### Data

All data is one JSON object in `localStorage` under the key `golf-strokes.v1`. Its shape is documented in a
comment at the top of the script in `index.html` (search for `db = {`). Old saves are migrated when the app
loads (`normalizeDb`, `migrateCourse`, `migrateStrokeIds`).

"Copy all data as JSON" and "Restore from backup" (under the gear on the home screen) export and import that
object. This is also the way to move data between the web app and the iOS app, which have separate storage.

## iOS and watch apps

### Requirements

- Xcode 26 with the iOS and watchOS SDKs
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Apple developer team `848GGC8882` (set in `ios/project.yml`) for running on devices

### Generate the Xcode project

The `.xcodeproj` is not in the repo. Generate it from `ios/project.yml`:

```sh
cd ios && xcodegen generate
```

Run it again after a fresh clone, after changing `project.yml`, and after adding, removing or renaming Swift
files. Editing an existing file needs no regeneration.

xcodegen also writes `watch/StrokeCounterWatch/Info.plist` and `StrokeCounterWatch.entitlements` from
`project.yml`. Change those settings in `project.yml`; edits to the generated files are overwritten.

### Targets

| Target | Bundle ID | Minimum OS | Sources |
| --- | --- | --- | --- |
| `StrokeCounter` (iOS) | `com.henrikdav.StrokeCounter` | iOS 17 | `ios/StrokeCounter/`, plus `web/` copied in as a folder |
| `StrokeCounterWatch` | `com.henrikdav.StrokeCounter.watchkitapp` | watchOS 10 | `watch/StrokeCounterWatch/` |
| `StrokeCounterWatchTests` | `com.henrikdav.StrokeCounter.watchkitapp.tests` | watchOS 10 | `watch/StrokeCounterWatchTests/` (unit tests) |

The watch app is embedded in the iOS app (`StrokeCounter.app/Watch/`). `web/` is copied into the iOS app when it
is built, so **a change to `index.html` reaches the iOS app only after a rebuild**. Both apps use HealthKit only
for the golf workout: the iPhone app launches the watch app with one when a round starts
(`HKHealthStore.startWatchApp`), and the watch app runs the workout session during the round. Nothing is saved
to Health.

### Build and install on devices

Open `ios/StrokeCounter.xcodeproj` in Xcode and run the `StrokeCounter` or `StrokeCounterWatch` scheme, or from
the command line:

```sh
cd ios
xcodebuild -project StrokeCounter.xcodeproj -scheme StrokeCounter \
  -destination 'id=<iPhone UDID>' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl list devices                    # device identifiers for the commands below
xcrun devicectl device install app --device <iPhone id> build/Build/Products/Debug-iphoneos/StrokeCounter.app
xcrun devicectl device install app --device <watch id> \
  build/Build/Products/Debug-iphoneos/StrokeCounter.app/Watch/StrokeCounterWatch.app
```

Things that have tripped this up before:

- **The Mac reaches the watch over Wi-Fi, not the cable.** "A connection to this device could not be established"
  usually means the watch is on a different Wi-Fi network than the Mac. A watch install sometimes times out once
  and works on the next try.
- **Developer Mode** must be on, on the watch as well as the phone (Settings → Privacy & Security).
- **The first connection** to a watch makes Xcode copy its symbol cache, which can take 10–20 minutes. Keep the
  watch awake and on its charger.
- **A new watch has to be registered** in the developer account (developer.apple.com → Devices, or
  `-allowProvisioningDeviceRegistration`) before its provisioning profile includes it. If the profile still
  lacks the watch, Xcode is using a stale cached team profile: move it out of
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles` and build again (the first build after that may fail
  once and the second succeed).
- **Fallback that always works:** install the iOS app on the phone, then install or update the watch app from the
  iPhone's Watch app → My Watch → Available Apps.

### Simulators

The watch only gets a round from a phone it is paired with. Run the iOS app and the watch app on a paired iPhone
and Apple Watch simulator; pair two with:

```sh
xcrun simctl pair <watch simulator id> <iPhone simulator id>
xcrun simctl list pairs
```

`transferUserInfo` is not delivered between simulators, so strokes logged on a simulated watch reach the
simulated phone through live messages or when the phone app comes to the foreground (it asks the watch to resend).
On real devices all paths work. HealthKit permission sheets can't be dismissed from the command line, which
blocks the screen in automated runs.

## Watch sync in short

- **Phone → watch:** whenever the web app saves, it sends a snapshot of the round opened last (holes, par, bag,
  strokes, locks, finished state) as the WatchConnectivity application context and, when the watch is
  reachable, as a live message. The watch can also ask for it.
- **Watch → phone:** every stroke added or removed, hole finished and late GPS fix is an event, sent queued
  (`transferUserInfo`) and live (`sendMessage`). The watch keeps each event until a snapshot shows the phone has it.
- **On the phone:** `WatchBridge.swift` stores incoming events in a file until the web app has applied them;
  `applyWatchEvents()` in `index.html` merges them by stroke id. Applying an event twice changes nothing, removed
  strokes are remembered, and changes made after a hole was locked or the round was finished are refused.

The full protocol (every message, field and rule, and how versions work) is in
[docs/watch-sync.md](docs/watch-sync.md).

## Testing

```sh
tests/run.sh              # every page; prints failures only
tests/run.sh -v scoring   # one page, every check
```

Each `tests/*.html` page loads `web/index.html` into an iframe (through `tests/harness.js`), sets up saved data,
calls the app's functions and clicks its buttons, and reports PASS or FAIL per check. `run.sh` serves the repo
with `python3 -m http.server`, opens each page in headless Chrome and exits 1 if any check fails. It needs
python3 and Chrome (set `CHROME=/path/to/chrome` if it isn't found).

| Page | Covers |
| --- | --- |
| `scoring` | Handicap strokes, gross, net with the net double bogey cap, Stableford, totals, export text |
| `storage` | Migrations on load, stroke ids, edit and delete by id, Restore from backup, export |
| `holes` | Done and the hole lock slider, marking the hole, the reminder on Done, distance to the hole |
| `finish-round` | Finishing and unlocking a round, and what is read-only while finished |
| `home` | Stats, Continue card, Past rounds and net badges, swipe to delete, settings |
| `navigation` | Where Back goes from the scorecard and hole views |
| `watch-sync` | Snapshots to the watch and `applyWatchEvents`: merging, removals, positions, locks, finished rounds |
| `suggest-club` | `teeClubs`: the likely tee club per hole sent to the watch (same hole on the course, else same par) |
| `gps` | The GPS watch: restarts after a denied error and on return to the app, the status pill |
| `gps-shim` | `ios/StrokeCounter/gps-shim.js` with a fake native bridge |
| `course-map` | The Map button and what it sends to the native map |
| `scorecard` | `parseScorecard` on Vision output recorded from rendered scorecards (`tests/fixtures`), and the scan flow in the course editor |

The iOS bridges are faked with a script put at the top of the app's `<head>` (`WATCH_BRIDGE`, `MAP_BRIDGE` in
`harness.js`).

The watch app's round logic (`RoundState`: what is shown, what is refused, when an event counts as confirmed) has
unit tests in `watch/StrokeCounterWatchTests/`, run on a watch simulator:

```sh
cd ios && xcodebuild test -project StrokeCounter.xcodeproj -scheme StrokeCounterWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

The rest of the Swift code (WatchConnectivity, GPS, HealthKit, the iOS bridges) is checked in the simulators.
The watch tests need macOS, so the GitHub workflow runs only the web tests.

The GitHub workflow runs the tests before every deploy and publishes nothing when one fails. Add a page, or
checks to a page, with each change to the rules.

## Conventions

- Commit messages, code comments and UI text are in English.
- Keep the web app in one file with no build step (see "Deploy" for why).
- Identifiers and comments follow the surrounding code; comments explain why, not what.
