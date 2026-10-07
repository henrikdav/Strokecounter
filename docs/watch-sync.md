# Watch sync protocol

How the iPhone app and the Apple Watch app keep one round in step. Protocol version **2**.

The phone owns the round. The watch shows the phone's round with its own unconfirmed changes on top, sends those
changes as events, and keeps each one until a snapshot from the phone shows it was applied. Every rule below
exists so that a stroke is never lost or counted twice, whichever messages arrive late, twice or not at all.

## The parts

| Where | Code | Role |
| --- | --- | --- |
| Web app (in the iOS app's web view) | `sendWatchSnapshot`, `applyWatchEvents` in `web/index.html` | Builds snapshots; merges events into the saved round |
| iOS app | `ios/StrokeCounter/WatchBridge.swift` | Relays between the web app and WatchConnectivity; keeps incoming events on disk until the web app has applied them |
| Watch app | `RoundState.swift` (the rules), `SyncClient.swift` (WatchConnectivity), `WatchStore.swift` (ties them together), `Models.swift` (the formats) in `watch/StrokeCounterWatch/` | Shows the round, logs events, keeps the outbox |

Inside the iOS app the web app and `WatchBridge` talk through the `watch` message handler:

- web → native `{ type: 'hello' }` when the page loads: native hands over any events that arrived meanwhile.
- web → native `{ type: 'snapshot', json }` at start and after every save.
- web → native `{ type: 'start-watch-app' }` when the player starts a new round or taps Continue: native calls
  `HKHealthStore.startWatchApp` with a golf workout configuration, which launches the watch app; its
  `handle(_ workoutConfiguration:)` starts the round's workout (or does so as soon as the round's snapshot
  arrives) and asks for the snapshot. Needs the watch on the wrist, unlocked and nearby; if it fails, the watch
  app is opened by hand. Not sent when the app reopens the active round by itself or for a finished round.
- native → web `applyWatchEvents(<array of events>)`, which answers `true` when the events were handled.

## Messages

All WatchConnectivity payloads are dictionaries with one JSON string inside, so their content is never limited to
property-list types.

| Direction | Channel | Payload | When |
| --- | --- | --- | --- |
| Phone → watch | `updateApplicationContext` | `{ "snapshot": "<snapshot JSON>" }` | Every new snapshot; again when the session activates, the watch app is installed, or the watch becomes reachable |
| Phone → watch | `sendMessage`, no reply | `{ "snapshot": "<snapshot JSON>" }` | The same moments, when the watch app is reachable (the context alone can be slow or lost) |
| Watch → phone | `sendMessage` with reply | `{ "type": "snapshot-request" }` → `{ "snapshot": "<JSON>" }` | Watch session activates or the phone becomes reachable. The phone answers from the last snapshot it saved, so this also works when the watch wakes the iPhone app in the background |
| Watch → phone | `transferUserInfo` | `{ "events": "<JSON array of events>" }` | Every new event; the whole outbox again when the watch session activates |
| Watch → phone | `sendMessage`, no reply | `{ "events": "<JSON array of events>" }` | Every new event, when the phone is reachable, so it shows up within a second |
| Phone → watch | `sendMessage` with reply | `{ "type": "flush" }` → `{ "events": "<JSON array of the outbox>" }` | iPhone app comes to the foreground, its session activates, or the watch becomes reachable |

`transferUserInfo` is queued by the system and delivered even when the receiving app is in the background or not
running; it is not delivered between simulators. The live messages need the other app running. Events are
therefore sent both ways and may arrive more than once, in any order between channels; applying them is
idempotent.

## Snapshot (phone → watch)

```json
{
  "v": 2,
  "round": {
    "id": "mcx3k2f9ab",
    "name": "Malmö Burlöv",
    "holes": [
      { "number": 1, "par": 4, "index": 7, "extra": 1,
        "position": { "lat": 59.331, "lng": 18.07, "acc": 4, "t": 1759500600000 } },
      { "number": 2, "par": 3, "index": null, "extra": null, "position": null }
    ],
    "currentHole": 2,
    "locked": [1],
    "finished": false,
    "strokes": {
      "1": [ { "id": "4f1c…", "club": "Driver", "mods": [], "t": 1759500000000, "lat": 59.33, "lng": 18.07, "acc": 5,
               "landing": { "lat": 59.3318, "lng": 18.07, "acc": 6 } } ],
      "2": []
    },
    "removed": ["9e2a…"]
  },
  "bag": ["Driver", "3W", "7i", "PW", "Putter"],
  "club": "Driver"
}
```

- `round` is the round opened last on the phone (`db.watchRoundId`), or `null` when there is none or it was
  deleted. Opening a finished round to look at it does not change which round the watch shows.
- `par` and `index` are `null` for a round without course data. `name` is the course name, else the round's label.
- `extra` is the hole's handicap strokes, worked out on the phone (`strokesReceived`) so the watch never repeats
  the handicap rules; `null` without a playing handicap and a hole index on every hole.
- `position` is where the hole (cup) was marked, on either device, with the time it was marked; `null` if not.
- `strokes` is keyed by real hole number. `mods` holds `chip`, `pitch`, `bunker`, `rough` in that order.
  `lat`/`lng`/`acc` appear only when the stroke has a position, `landing` only when the shot's distance was locked
  (Stop on the phone, a tap on the distance on the watch).
- `locked` lists holes finished with Done. For a finished round it lists every hole, so an older watch app also
  treats the whole round as read-only.
- `removed` lists every stroke id removed on either device (tombstones). They never come back.
- `bag` is the phone's bag; `club` the club selected on the phone, used until a club is picked on the watch.

## Events (watch → phone)

Every event has `v`, `type`, `roundId` and `hole` (the real hole number). Times `t` are milliseconds since 1970 on
the watch's clock.

| `type` | Other fields | Meaning |
| --- | --- | --- |
| `add` | `stroke`: `{ id, club, mods, t, lat?, lng?, acc? }` | A stroke logged on the watch. `id` is a lowercase UUID made on the watch; the position is the watch's own fix, when it had one no older than 30 s |
| `remove` | `id`, `t` | A stroke removed with Undo |
| `finish` | `t` | The hole was finished on the watch (Next hole / Finish hole) |
| `position` | `id`, `position`: `{ lat, lng, acc }` | A fix that arrived within 10 s after a stroke logged without one |
| `landing` | `id`, `position`: `{ lat, lng, acc }`, `t` | The shot's distance was locked on the watch: where the watch was then is where the shot landed (v2) |
| `mark` | `position`: `{ lat, lng, acc }`, `t` | The hole was marked on the watch (Finish hole screen) (v2) |

## Rules on the phone (`applyWatchEvents`)

1. **Version.** If any event has a higher `v` than the app supports, nothing in the batch is applied and the call
   answers `false`; the iOS app keeps the events queued until the iPhone app is updated, and the user is told to
   update it. Events without `v` come from before versioning and count as 1.
2. **Unknown round.** Events for a round the phone doesn't have are ignored.
3. **add.** Ignored if the stroke id is already on the hole or in `removed`. Otherwise inserted in playing order
   by `t`, whichever device logged the strokes around it. Unknown modifiers are dropped; Penalty takes none.
4. **remove.** Takes the stroke out and adds its id to `removed`, so an `add` arriving later stays out.
5. **position.** Fills in a position only if the stroke has none.
6. **landing.** Sets `stroke.landing`, as Stop does on the phone (`measureLanding`): only once, and never for a
   putt, a penalty stroke or a stroke without a position. The phone then works out the shot's distance itself
   (`shotDistance`), so scorecard and export are the same as for a distance measured on the phone.
7. **mark.** Sets `round.holePositions[hole]`, as Mark hole does on the phone. The newest mark wins by `t`,
   whichever device made it and whatever order marks arrive in.
8. **finish.** Locks the hole (recording `lockedAt` from the event's `t`) and moves the phone's current hole on,
   if it was that hole and not the last. Repeats change nothing.
9. **Locks and finished rounds.** A change made at a time `t` (add, remove, landing, mark) is refused when the hole was locked, or the round
   finished, by then (`lockedAt`, `finishedAt`). A change made earlier but delivered later still counts, so a slow
   sync cannot lose a stroke that was played. A refused `add` is put in `removed`, so the watch drops it. Holes
   locked before lock times were recorded count as locked from the start. A `finish` on a finished round is
   ignored.
10. After applying, the phone saves (which sends a new snapshot) and redraws, unless a sheet is open, so text being
   typed is not lost. When nothing changed it still sends a snapshot, so the watch can stop resending.

## Rules on the watch

- **What it shows** is the snapshot with the outbox on top: strokes removed here are hidden, strokes added here
  are shown, in order of `t`. The current hole is the phone's, or the hole after one finished here and not yet
  confirmed.
- **Confirmation.** On each snapshot the watch drops from its outbox every event the snapshot shows as handled:
  - `add`: the stroke is in the round, or in `removed` (applied, or refused).
  - `remove`: the id is in `removed`, or the hole is locked (refused).
  - `finish`: the hole is in `locked`.
  - `position`: the stroke has a position, or is in `removed`.
  - `landing`: the stroke has a landing, is in `removed`, or the hole is locked (refused).
  - `mark`: the hole's `position` is at least as new as the mark (applied, or a newer mark won), or the hole is
    locked (refused).
  Events for another round are dropped too; they were already queued for delivery when they were made.
- **Locks.** The watch refuses to log or remove strokes on a locked hole, or in a finished round, and shows
  "Hole locked" or "Round finished". The phone enforces the same rules (above), so a stale watch cannot get round
  them.
- **Version.** A snapshot with a higher `v` than the watch app supports is ignored: the round already on the watch
  keeps working, events from it are still accepted by the newer phone, and the watch asks to be updated.
- **Shot distance.** The hole screen shows the distance from the hole's last stroke to the watch's current fix
  (no older than 30 s), worked out on the watch with the phone's formula (`meters`, haversine) and shown as the
  phone does (`fmtDist`: whole meters, "≈" when the two accuracies add up to more than 25 m). Nothing for a
  putt, a penalty stroke or a stroke without a position. Once the landing is set it shows that distance, fixed.
- **Workout.** The golf workout session (and with it background GPS) starts once the hole screen has been shown
  or the iPhone app launched the watch app for a round. From then on it follows the round: it runs while the
  round is not finished, ends when the snapshot says `finished` or the round is removed, and when another
  unfinished round arrives it ends the old session and starts one for the new round.

## What is stored where

| Where | Key / file | What |
| --- | --- | --- |
| Web app | `localStorage` `golf-strokes.v1` | The rounds, including `removedStrokeIds`, `locked`, `lockedAt`, `finished`, `finishedAt`, `watchRoundId` |
| iOS app | `UserDefaults` `watchSnapshot` | The last snapshot, to answer `snapshot-request` |
| iOS app | `Application Support/watch-pending.json` | Events received but not yet applied by the web app |
| Watch | `UserDefaults` `snapshot`, `outbox`, `lastClub` | The last snapshot, unconfirmed events, the club picked on the watch |

## Versioning

`v` is `WATCH_PROTOCOL` in `web/index.html` and `WatchProtocol.version` in `Models.swift`; change both together.

- **Same version:** adding an optional field. Both sides ignore fields they don't know (JavaScript reads only
  what it uses; Swift's `Codable` skips unknown keys), and new fields must be safe to leave out.
- **New version:** removing or renaming a field, changing its meaning or unit, or a new event type an older phone
  would mishandle. Then each side refuses what it can't read, as described above, without losing data.

| Version | Change |
| --- | --- |
| 1 | First versioned protocol |
| 2 | Events `landing` and `mark`; snapshot fields `extra` and `position` on holes, `landing` on strokes |

The watch app is updated separately from the iPhone app (and sometimes later), so either side may be the newer one.

## Testing

`tests/watch-sync.html` covers the phone side: snapshots, every rule of `applyWatchEvents`, and versions
(`tests/run.sh watch-sync`). `watch/StrokeCounterWatchTests/RoundStateTests.swift` covers the watch's rules: what
is shown, what is refused, confirmation and versions. The transport is checked with a paired iPhone and Apple
Watch simulator; see the README for the simulators' limits.
