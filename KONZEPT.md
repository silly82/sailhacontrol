# Concept: Home Assistant control for SailfishOS

Started: 2026-08-28

> This is the English version of the design concept and the dated development
> log. The original German text up to and including section 24 is kept in
> [`KONZEPT_DE.md`](KONZEPT_DE.md) as a historical record; from section 25
> onwards, new entries are written here in English only.

## 1. Goal

A native SailfishOS app (Silica QML) that controls a local Home Assistant
instance. Not a clone of the Companion app, but a lean client cut down to the
essentials -- the focus is quick access to a handful of entities rather than
feature parity with the official Android/iOS app.

**Connection:** local network only (REST/WebSocket straight against the HA
instance, no Nabu Casa or reverse proxy). Remote access is deliberately
deferred to stage 3 and optional even there -- that avoids a TLS/proxy setup
before the core client works at all.

**Auth:** a long-lived access token (created in HA under Profile → Security),
sent as an `Authorization: Bearer <token>` header. No OAuth flow -- for a
single-user client on your own device that is sufficient, and far simpler than
reimplementing HA's full OAuth2 login flow natively.

## 2. Stages

### Stage 1 -- basic client (local, manual) -- **scaffold in place, see section 3**
- Config page: HA URL + long-lived access token
- List of all `light`/`switch` entities (REST `GET /api/states`)
- Toggle via service call (`POST /api/services/<domain>/toggle`)
- Manual pull-to-refresh, no push

### Stage 2 -- dashboard & real time
- WebSocket API instead of polling → live state updates
- Grouping by HA areas/rooms (area registry)
- More domains: climate (target temperature), cover, media player (basic controls)
- Scenes/scripts as favourite tiles
- Local SQLite cache for an offline view (last known state)

### Stage 3 -- system integration & remote
- Lock screen / events view widget for one or two favourite entities
- Push notifications from HA → Sailfish. Two options weighed up:
  - **Option A** (own relay server + native background service, permanent
    connection): low latency, but a lot of work -- it needs an RPM outside the
    Sailjail sandbox (not store-compatible).
  - **Option B** (periodic background sync via Nemo Keepalive,
    `BackgroundActivity`): not real push, delay on the order of the poll
    interval, but store-compatible and builds directly on the stage 1 REST
    client.
  - **Decision 2026-08-28: started with option B** (see section 4) -- option A
    stays available later should seconds-rather-than-minutes latency turn out
    to be necessary.
- Optional: device tracker (report location to HA, presence detection)
- Remote access from outside the local network (Nabu Casa or an own reverse
  proxy with TLS)

## 3. Update 2026-08-28: project scaffold created

Skeleton created under `/home/silly/sailhacontrol`, along the same lines as
`sailtalerwallet` (`.pro`/`.desktop`/`rpm/*.spec` following the standard SFOS
template, `org.nemomobile.configuration` for settings persistence).

**Architectural difference to sailtalerwallet:** no native C++ bridge object is
needed -- Home Assistant's REST API is plain HTTP+JSON, so QML's own
`XMLHttpRequest` suffices (`qml/lib/HaApi.js`). `main.cpp` therefore only loads
the QML root view, without `qmlRegisterType`/context properties.

**State of the files:**
- `harbour-hacontrol.pro`, `.desktop` (Permissions=Internet, no
  camera/location), `src/harbour-hacontrol.cpp` -- boilerplate, untested
- `qml/pages/SettingsPage.qml` -- HA URL + token, stored via
  `ConfigurationValue` (plaintext -- good enough for a local prototype, see TODO)
- `qml/pages/FirstPage.qml` -- entity list (light/switch) with toggle switch,
  pull-to-refresh, error display
- `qml/lib/HaApi.js` -- `getStates()`, `callService()`
- `rpm/harbour-hacontrol.spec` -- version 0.1

**Still open / unverified:**
- **No app icon** -- `SAILFISHAPP_ICONS` in the `.pro` references
  `icons/<size>/harbour-hacontrol.png`, and those files do not exist yet. Must
  be added before the first `sfdk build`/packaging (or the line commented out
  temporarily).
- **Not built or tested yet** -- unlike sailtalerwallet there is no real test
  device setup for this project yet. Next step: build against a SailfishOS
  target with `sfdk` and verify against a real HA instance on the local network
  (enter URL + token in settings, trigger a refresh, check a toggle).
- Token storage via `org.nemomobile.configuration` is plaintext under
  `~/.config/harbour-hacontrol/`. Accepted for stage 1; if the device is
  shared, switch to the Sailfish Secrets API.
- No git repo initialised -- deliberately left open until the first build is
  verified against real hardware.

## 4. Update 2026-08-28: stage 3 / option B (background poll + notification) implemented

Started before stage 1 had been verified on hardware -- explicitly requested
that way. Implemented:

- **`qml/pages/FirstPage.qml`**: every entity now has a context menu ("notify
  on change" / "disable notification") which adds or removes the entity ID in
  the `ConfigurationValue` `/apps/harbour-hacontrol/watchedEntities`
  (comma-separated). Watched entities show a small "notified" label next to the
  switch.
- **`qml/harbour-hacontrol.qml`**: `BackgroundJob` (from `Nemo.KeepAlive`, see
  section 5 -- originally written as `BackgroundActivity`/
  `org.nemomobile.keepalive`, which was wrong) with `frequency: TenMinutes`,
  `enabled: true`. On every `onTriggered`: `HaApi.getStates()` against all
  watched entities, compared with the last known state (persisted as JSON in
  the `ConfigurationValue` `/apps/harbour-hacontrol/lastKnownStates`, so that
  an app restart does not report a "change" for every watched entity again). On
  an actual change: a dynamically created `Notification` object
  (`org.nemomobile.notifications`) via `Qt.createQmlObject()`, then
  `.publish()`.
- **`rpm/harbour-hacontrol.spec`**: added `Requires:
  nemo-qml-plugin-notifications-qt5, libkeepalive` (pure QML plugins, no
  BuildRequires needed since nothing links against them).

**Still open / unverified (in addition to section 3):**
- **Core risk, to be checked on hardware**: `BackgroundActivity` only keeps the
  process awake while it is resident anyway (foreground or recently minimised)
  -- an app process fully terminated by the system is **not** restarted by it.
  For "really in the background, app never opened" you would need a separate
  daemon with autostart/D-Bus activation (which would effectively be option A).
  Has to be observed on the real test device: does the process stay resident
  long enough after "close app" (home gesture) for ten-minute polls to arrive
  at all?
- Unclear whether the asynchronous `XMLHttpRequest` call reliably finishes
  within the IPHB wakeup window before the CPU suspends again -- a known
  uncertainty with `BackgroundActivity` + network I/O, not conclusively settled
  from documentation.
- The module names (`org.nemomobile.keepalive`, `org.nemomobile.notifications`)
  match the legacy namespace style already confirmed in sailtalerwallet
  (`org.nemomobile.configuration`), but the exact QML API (`run()`/`wait()`
  state machine of `BackgroundActivity`) was written from memory, not verified
  against SDK docs -- the first build will expose that.
- No picker for "which entity to watch" outside FirstPage -- you have to see
  the entity in the list already (light/switch) to mark it via the context menu.

## 5. Update 2026-08-28 (part 2): SDK installed, first build + emulator test

SailfishOS SDK 3.13.5 installed locally under `/home/silly/SailfishOS` (`sfdk`
at `/home/silly/SailfishOS/bin/sfdk`, not in PATH). Available targets:
`SailfishOS-5.1.0.11-{aarch64,armv7hl,i486}` and `SailfishOS-5.0.0.62-aarch64`.
The emulator (`SailfishOS-5.1.0.11`) is i486 -- emulator tests must be built
against the **i486 target**, not aarch64 (the RPM for the real Jolla Phone
stays aarch64, see the sailtalerwallet workflow).

**Placeholder icons generated** (`icons/<size>/harbour-hacontrol.png`, via
ImageMagick, blue background + "HA" lettering) -- placeholders only, not a real
app icon design.

**Build and deploy workflow that worked:**
```
sfdk config target=SailfishOS-5.1.0.11-i486
sfdk config specfile=rpm/harbour-hacontrol.spec
sfdk build
sfdk config device="Sailfish OS Emulator 5.1.0.11"
sfdk deploy --sdk          # builds, rsyncs RPMS/ to the emulator, installs
```
Important: `sfdk config <var>=<value>` only sets "session scope", which does
**not** persist across separate shell invocations (every Bash tool call is a
fresh shell) -- all three `config` lines and the actual command have to run in
the same shell session (chained with `&&`), otherwise the standing **global**
default applies (which here happened to point at an unrelated project,
`harbour-nemoai`, presumably left over from an earlier session).

**Emulator access without `devel-su`:** unlike the Jolla Phone in
sailtalerwallet, this emulator image has no `devel-su` binary -- passwordless
`sudo` as `defaultuser` works instead (e.g. `sudo -n journalctl -f`). The SSH
key is at `~/SailfishOS/vmshare/ssh/private_keys/sdk`, port `2223`, host
`127.0.0.1`.

**Two real bugs found and fixed** (exactly the point of the test -- the stage 3
QML had been written "from memory", see section 4):
1. `import org.nemomobile.keepalive 1.0` does **not** exist in SFOS 5.1 -- only
   `Nemo.KeepAlive` does. The corresponding RPM package is called `libkeepalive`
   (not `nemo-qml-plugin-keepalive-qt5`, which simply does not exist).
2. Within `Nemo.KeepAlive` the type is called **`BackgroundJob`**, not
   `BackgroundActivity`, and it has a different API: `enabled`/`frequency`/
   `onTriggered`/`finished()` instead of `run()`/`wait()`/`onRunning`. The
   `run()`/`wait()` pattern was remembered from an older/different keepalive
   API and does not exist in this version.

Both fixes applied to `qml/harbour-hacontrol.qml` and
`rpm/harbour-hacontrol.spec`, then rebuilt/redeployed/restarted -- the journal
then shows **no** module or QML errors any more, only two harmless deprecation
warnings (`org.nemomobile.configuration`/`org.nemomobile.notifications` still
work but are marked legacy -- migrating to `Nemo.Configuration`/
`Nemo.Notifications` would be a clean, non-urgent follow-up).

**What this test did NOT cover** (still open):
- No real HA instance available -- `FirstPage` was only seen in its
  unconfigured state (the "not configured yet" hint), never tested against
  real entities (refresh, toggle, context menu interaction, an actual
  `Notification` firing).
- No UI interaction tested (no display/VNC attached in this environment) --
  only process startup + journal log checked. `ContextMenu` in `FirstPage.qml`
  is only instantiated on an actual long press and was therefore not part of
  this test.
- The core risks named in section 4 (process residency of
  `BackgroundJob`/keepalive in the background, whether the async
  `XMLHttpRequest` finishes in time) remain unsettled -- that can only be
  observed on real hardware over a longer period, not in the emulator during a
  short test session.

## 6. Update 2026-08-29: area grouping, sensors, v0.2 release

Verified against the user's real HA instance (reachable on the local network
from both the emulator and the real device -- no NAT problem). Two API bugs
found and fixed during the first emulator run (`Nemo.KeepAlive` instead of
`org.nemomobile.keepalive`, `BackgroundJob` instead of `BackgroundActivity` --
details in section 5). After that:

- **Area/room grouping + sensors** (jumping ahead to stage 2) via
  `HaApi.getAreaMap()`: the `/api/template` endpoint with Jinja2 `area_name()`
  rather than the WebSocket API, to stay REST-only. HA's sandboxed Jinja blocks
  `dict.update()` as "unsafe" -- the workaround is the `namespace(items=[])` +
  list concatenation idiom. `sensor` entities with a `device_class` of
  `temperature`/`humidity`/`pressure`/`atmospheric_pressure` are shown
  read-only with their value (one decimal) + unit. Collapsible per room via a
  flat `ListModel` (header and entity rows mixed) instead of nested list
  models, because of SilicaListView virtualisation with sometimes >100 entities
  per instance.
- **`ScrollingLabel` component** (`qml/components/ScrollingLabel.qml`) that
  scrolls long names through once. **Bug found and fixed**: a missing `height`
  (only `clip: true`) made the text completely invisible -- spotted with the
  help of a screenshot, after the user reported "I see no text".
- **Toggle timing fix**: `postToggleRefreshTimer` (1s) instead of an immediate
  refresh after `toggle()` -- HA's service response only confirms that the
  command was accepted, not that Zigbee/Matter devices have already reported
  the new state back. Confirmed by the user: "toggle works cleanly now".
- **Real device (Jolla Phone, aarch64)**: the first installation got stuck
  inside the `sailjail` wrapper (never exec'd through to the actual binary) --
  the cause was a `lipstick-windowprompt` permission dialog (internet access)
  that had to be confirmed on the device screen. That dialog does not appear on
  the emulator (dev mode skips it). After confirming: the app runs cleanly,
  looking identical to the emulator (room list, expand/collapse, sensors).
- **v0.2 release**: public repo created at `github.com/silly82/sailhacontrol`,
  three RPMs built (i486/emulator, aarch64/newer phones -- both tested;
  armv7hl/older phones -- builds cleanly but **untested**, as no armv7hl
  hardware was available). Documentation (`README.md`) written in English, with
  a Swiss Standard German section after it (no "ß", `ss` instead).

## 7. Update 2026-08-29 (part 2): swipe navigation, v0.3 release

- **Swipe instead of a pull-down menu item**: the sensor overview was initially
  a separate `SensorsPage.qml` pushed from the pull-down menu. Rebuilt as two
  side-by-side sub-views (`qml/views/RoomsView.qml`,
  `qml/views/SensorsView.qml`), switched by a horizontal swipe inside a shared
  `SilicaFlickable` (`flickableDirection: HorizontalFlick`, manual snapping on
  `contentX` via `NumberAnimation`) within the now very thin `FirstPage.qml`.
  Settings stays reachable from both sub-views through their own pull-down
  menus. Confirmed by the user after testing on the emulator AND the real
  device: "works well".
- **v0.3 release**: version bumped in `rpm/harbour-hacontrol.spec`, `License:`
  corrected from a placeholder to `MIT` (with the corresponding `LICENSE` file
  added), `URL:` set to the real GitHub repo URL (previously an
  `http://example.org/` placeholder). All three RPMs (i486/aarch64/armv7hl)
  rebuilt and published via `gh release create` with notes.

## 8. Update 2026-08-29 (part 3): WebSocket live updates (the rest of stage 2)

Developed in its own branch (`feature/websocket-live-updates`), merged back to
`master` after testing on the emulator and the real device.

- **Verify up front instead of guessing**: unlike the earlier `BackgroundJob`
  episode, this time the exact QML API was read out of the SDK build target's
  `plugins.qmltypes` *before* writing any code (`sfdk tools exec ... cat
  .../QtWebSockets/plugins.qmltypes`). The type is called `WebSocket` (`import
  QtWebSockets 1.0`), with properties `url`/`status`/`active`, signals
  `textMessageReceived`/`statusChanged`, and the method `sendTextMessage()`.
  **A trap along the way**: `zypper` reported the module as installed in the
  build target, yet the actual `.so` was missing -- `zypper install --force`
  pulled it in. Packages: `qt5-qtdeclarative-import-websockets` (QML plugin) +
  `qt5-qtwebsockets` (C++ lib), both added as `Requires:` in the spec -- on the
  real device `pkcon` correctly pulled the QML plugin package in automatically
  at install time.
- **Architecture**: REST (`refresh()`) remains the source for structure (rooms,
  ordering, initial state); the WebSocket then only delivers deltas
  (`state_changed` events) which are patched per row into `entriesModel`
  (`applyStateChange()`), without rebuilding the list. The auth handshake
  (`auth_required` → `auth` reply with the token → `auth_ok` →
  `subscribe_events`) runs entirely in `qml/views/RoomsView.qml`. Reconnect
  after 5s on `Closed`/`Error` by restoring `active` via `Qt.binding()`, rather
  than permanently breaking the binding to `configured` with a plain value
  assignment.
- **Known limitation**: HA's `subscribe_events(state_changed)` has no
  server-side domain filtering -- on the user's 1499-entity instance, events
  for entities outside our model arrive constantly (e.g. energy sensors every
  second) and are discarded by a linear scan. Harmless at the list sizes
  involved here, but a candidate for later optimisation (an `entityId`→index
  map) should battery/CPU load become noticeable on very large instances.
- **Verified**: confirmed by the user on the emulator AND the real device --
  switching a light externally (via HA's web UI or a physical switch) shows up
  in the app immediately, without a manual pull-to-refresh.

## 9. Update 2026-08-29 (part 4): extended light controls, v0.4 release

Developed in its own branch (`feature/light-detail-controls`).

- **A submenu instead of extending the toggle**: tapping the name of a `light`
  entity (lights only, not switches) opens
  `qml/pages/LightDetailPage.qml` with brightness/colour-temperature sliders
  and a button to pick a colour -- the toggle switch stays unchanged.
  `ListItem.onClicked` + `menu:` (context menu) coexist without an additional
  `MouseArea`, since `ListItem` supports both at once; `onClicked` fires for
  taps outside the switch area (the switch consumes its own tap first).
- **Capability detection** via `attributes.supported_color_modes` (brightness:
  any mode other than `onoff`; colour temperature: `color_temp`; colour:
  `hs`/`rgb`/`xy`/`rgbw`/`rgbww`) -- only controls the light actually supports
  are shown.
- **Kelvin instead of mired, verified**: before writing code, the real light
  entity attributes were queried from the HA instance (`curl
  .../api/states`). This HA version consistently uses
  `min_color_temp_kelvin`/`max_color_temp_kelvin`/`color_temp_kelvin` (no more
  `mireds`) -- so `light.turn_on` is called with `color_temp_kelvin` rather
  than `color_temp`.
- **Colour picking via the stock Silica component** `ColorPickerPage` (`import
  Sailfish.Silica 1.0`, no hand-built colour picker) -- its API verified
  beforehand via `sfdk tools exec ... cat ColorPickerPage.qml` (`signal
  colorClicked(color color)`, pushed as an inline `Component`).
- **Bug found and fixed** (user feedback: "the state only seems right after the
  light is on"): HA reports `brightness`/`color_temp_kelvin`/`rgb_color` as
  `null` while the entity is `state: off` -- not a limitation of this app but
  HA's data model (many integrations visually "forget" the last value even when
  it still exists internally). Fix: a hint on the detail page, visible only
  when `!entityIsOn`, explaining that the slider then shows a starting value
  rather than a stored setting, and that moving it switches the light on.
- **v0.4 release**: version bumped, branch merged to `master`, all three RPMs
  rebuilt and published.

## 10. Update 2026-08-31: lock screen widget investigated -- not possible, notification action instead

**Research result before building anything**: a real lock screen widget as on
Android does not exist for Sailjail-sandboxed third-party apps. The entire lock
screen QML (`LockScreen.qml`, `LockscreenBackground.qml`, ...) lives in
`lipstick-jolla-home-qt5`, i.e. in the system itself -- no `Loader`/plugin
extension point for third-party content was found (`grep` for
`loader|plugin|thirdparty` in `LockScreen.qml` turned up nothing). So the
original concept wording "lock screen widget" was not literally implementable
-- agreed with the user: a **notification with an action button** instead,
which toggles a watched entity straight from the lock screen (expanded
notification) without opening the app.

- **Technical route**: `Nemo.Notifications`' `Notification.remoteActions`
  (a property holding an array of `remoteAction(name, displayName, service,
  path, iface, method, arguments)` descriptors) plus `Nemo.DBus`'
  `DBusAdaptor` -- the latter allows offering a D-Bus service **entirely from
  QML** (no C++ extension needed). The pattern (function names inside the
  `DBusAdaptor` block automatically become D-Bus methods) was verified against
  `jolla-settings/settings.qml` in the SDK target, not guessed.
- **Implementation** in `qml/harbour-hacontrol.qml`: a `DBusAdaptor` with
  `service/path/iface = org.example.hacontrol` (which follows from the bus name
  Sailjail already assigns the app, see `[X-Sailjail]` in the `.desktop` file)
  and a `toggleEntity(entityId)` function that calls the existing
  `HaApi.callService(...toggle...)`. `notifyStateChange()` now attaches
  `remoteActions` with a "toggle" action to every notification.
- **Same constraint as the background poll itself**: this only works while the
  app process is resident (there is no D-Bus activation `.service` file) -- not
  a new limitation, but the same one that applies to stage 3 / option B overall.
- **Verified in two steps**: (1) `toggleEntity` called manually via `dbus-send`
  against a real entity (`light.wohnen`) -- the light really came on, confirmed
  via a REST API query, then switched back off. (2) The complete path
  end-to-end through a real background poll cycle:
  `watchedEntities`/`lastKnownStates` prepared in dconf, the user toggled the
  entity externally, and after the next poll `lastKnownStates` showed the new
  value while `NotificationActionRow.qml` (the Lipstick component that renders
  action buttons on notifications) appeared in the journal at exactly the poll
  timestamp -- proof that the notification with its visible button really was
  published.
- **New `Requires:`**: `nemo-qml-plugin-dbus-qt5` added to the spec.

## 11. Update 2026-08-31 (part 2): remaining concept item deferred

That covers every concept item from stages 1-3 except one:

- **Remote access** (access from outside the local network, e.g. via Nabu Casa
  or an own reverse proxy, see sections 1/2). **Deferred as a future TODO
  without priority** -- explicitly not tackled now at the user's request. No
  technical blocker known, just deliberately not prioritised.

## 12. Update 2026-08-31 (part 3): a real app icon instead of the placeholder, v0.6

Until now just an ImageMagick placeholder (blue square + "HA" lettering, see
section 5). The user linked the official Sailfish icon design resources
(`Sailfish-Apps-icon-template.zip`, sailfishos.org/design/icons/, the "App icon
story" PDF), pointing out that the icon silhouette is deliberately **not a
simple rounded rect/squircle** but a family of organic shapes defined in the
official template -- not something to estimate by eye.

- **Exact path taken from the template**: downloaded
  `icon-launcher-template.svg` (86x86 space) and extracted the silhouette path
  verbatim -- two opposite corners with a large organic quarter-circle radius
  (~42.7px), the other two with a normal small rounding radius (~1.4px).
- **Rendering pitfall**: ImageMagick's built-in SVG parser (MSVG) does not
  handle `<linearGradient>` reliably -- the background came out solid black
  instead of a gradient. `rsvg-convert` (the CLI) was not installed, only the
  library, and no `pip`/`cairosvg` was available. Solution: `python3-cairo`
  (pycairo) was already present as a system package -- path, gradient and motif
  drawn directly through the pycairo API instead of going through an SVG
  parser, which sidesteps the problem entirely.
- **Design**: navy-to-HA-blue diagonal gradient (`#1B3A57` → `#41BDF5`), white
  house silhouette motif, centred. Checked to still read clearly at 86px (the
  smallest launcher size).
- **Reproducible**: the generator script is committed at
  `icons/source/generate-icon.py` (`python3 icons/source/generate-icon.py`
  regenerates all four sizes straight into `icons/<size>x<size>/`), rather than
  just dropping finished PNGs with no provenance.
- The proposal was shown to the user as an image preview and confirmed
  directly, then adopted.
- **Addendum**: the file on disk and in the package was correct immediately
  (verified via `raw.githubusercontent.com` too), yet the launcher on both
  devices kept showing the old "HA" square -- the cause was an in-memory pixmap
  cache in the long-running `lipstick` process (active on the emulator since
  the very first install days earlier) which is never invalidated when the same
  file is overwritten. Fix: `systemctl --user restart lipstick` on both devices
  (no `devel-su` needed on either -- the user session's systemd does not
  require root for this).

## 13. Update 2026-08-31 (part 4): preparing for Jolla Store/Harbour submission

The user pointed at the official Harbour guidelines. Researched via
`docs.sailfishos.org/Develop/Apps/Harbour/` (allowed APIs, allowed permissions)
-- and, crucially, **ran the official validator locally** rather than only
reading the docs:
```
sfdk check -s harbour <rpm-file>
sfdk check -s rpmlint <rpm-file>
```
That surfaced concrete problems that had been invisible until then:

- **Blocking error**: `Nemo.KeepAlive 1.1` is **not allowed** according to
  Harbour's allowed-APIs list -- only `Nemo.KeepAlive 1.2` is. The import in
  `harbour-hacontrol.qml` was raised accordingly.
- **Deprecation warnings cleaned up**: `org.nemomobile.configuration` →
  `Nemo.Configuration` (5 files), `org.nemomobile.notifications` →
  `Nemo.Notifications` -- previously just cosmetic log lines, now confirmed as
  real Harbour warnings and fixed. Verified on the emulator afterwards: no more
  deprecation lines in the journal.
- **rpmlint errors fixed**: `no-changelogname-tag` (missing `%changelog`
  section -- added) and `explicit-lib-dependency libkeepalive` (rpmlint wants
  the soname form `Requires: libkeepalive.so.1` instead of the package name).
  **The soname form was reverted**: it passed the local checks just as well but
  broke the real installation on the phone ("nothing provides
  libkeepalive.so.1" -- zypper there wanted the `()(64bit)`-qualified form).
  The package-name `Requires: libkeepalive` stays, and the rpmlint warning is
  deliberately accepted (it is only `TreatErrorsAsWarnings` anyway, not a hard
  blocker).
- **`%license` attempt discarded**: `%license LICENSE` (the Fedora convention,
  installing into `/usr/share/licenses/...`) was rejected by the Harbour
  validator with "Installation not allowed in this location" -- Harbour's path
  whitelist is narrower than general Fedora rules. The `License:` tag in the
  spec header is enough; no separate file is installed.
- **Unstripped-binary warning fixed**: `sfdk build` (a dev workflow) sets
  `QMAKE_STRIP=:` (a no-op) on the qmake call for faster iteration -- an
  explicit `%{__strip}` was added to the `%install` section rather than relying
  on automatic stripping.
- **Result**: `sfdk check -s harbour` AND `-s rpmlint` pass cleanly for all
  three architectures (i486/aarch64/armv7hl) -- zero errors, zero rpmlint
  warnings apart from the deliberately accepted `explicit-lib-dependency`.
  Installed and started on both the emulator and the real device, no new
  runtime errors.
- **Still open for an actual submission** (not part of this preparation):
  setting up a Jolla account + Harbour access, and settling the store question
  itself (e.g. whether an app that primarily controls a private/local HA
  instance belongs in the store at all, or whether GitHub releases remain the
  better distribution model -- that decision is the user's).

## 14. Update 2026-08-31 (part 5): store listing assets prepared

New `store/` folder (no code, not part of the RPM): three screenshots from the
SDK emulator (room list, sensor overview, light detail sliders -- the latter
two required manual navigation by the user, since touch input cannot be
simulated), plus listing description text in English and German.

- **Privacy question asked up front**: the screenshots show the real room and
  device names of the user's HA instance (including a person's name as a room
  label). Explicitly asked before committing rather than just publishing --
  confirmed by the user: "as it is, that's fine".
- Harbour's FAQ documents no fixed screenshot dimensions/formats or category
  list (unlike the RPM/API rules, there is no automated validator for this) --
  `store/README.md` records that explicitly as unverified rather than inventing
  numbers.

## 15. Update 2026-09-03: store assets refined against the real form

The user posted the actual Harbour submission form (Title/Details/
Categorization/Binaries/Compatibility/Visual assets/Contact details/Publish
settings), which replaced guesswork with knowledge:

- **Summary field discovered**: a separate field from Description, with a
  200-character limit -- previously missed, `summary-en/de.txt` added.
- **New screenshots**: real device instead of emulator (1032x2272 native),
  upscaled to 1080x2378 because the form demands "at least 1080px wide" and the
  phone's native width falls just short.
- **Description cleaned up**: the title line ("HA Control") and the GitHub link
  at the end were removed, since both have their own form fields (Title, Open
  source project URL) -- no duplication.
- **Category left open**: the dropdown options were never seen; the user fills
  that in.
- The account already exists, and the **user submits manually** through the web
  UI -- not an automation candidate.

## 16. Update 2026-09-07: thermostat control (climate domain)

Analogous to the light controls: tapping the name of a `climate` entity opens
`qml/pages/ThermostatDetailPage.qml` with a target-temperature slider
(`min_temp`/`max_temp`/`target_temp_step` from the attributes) and a mode
selector (`ComboBox` + `ContextMenu` + `Repeater` over `hvac_modes`). Before
writing anything, the real climate attributes were checked against the HA
instance via curl (6 thermostats, `hvac_modes` ranging from `["off","heat"]` to
`["auto","heat","off"]`, `target_temp_step` not always present -- fallback
0.5).

**Two real bugs found and fixed during testing** (user feedback "Mode is still
missing, Off Heat", then verified by screenshot):

1. QML `ListModel` roles are **type-locked** (the first value fixes the type)
   -- the `value` role had already been fixed as String by the toggle/sensor
   rows, but a climate row's target temperature came in as a Number
   (`s.attributes.temperature`), producing `Can't assign to existing role
   'value' of different type [Number -> String]` warnings in the journal, with
   a wrong/missing display as the symptom. Fix: always write the target
   temperature into the row via `String(...)`.
2. **The mode display stayed empty** even though the "Mode" label was visible:
   `ThermostatDetailPage.qml` read `attributes.state`, but HA's `state` (for
   climate == the current hvac_mode) sits as a **sibling field next to**
   `attributes`, not inside it -- so it was always `undefined`. Fix: a separate
   `hvacMode` field in `RoomsView.qml`'s row objects, passed through separately
   as the `entityHvacMode` property.
- Verified on the emulator (screenshot: "Mode Off" correct) and the real device
  (user: "works, setting the temperature works"). `sfdk check -s harbour`/`-s
  rpmlint` still clean apart from the already-accepted `libkeepalive` warning.

## 17. Update 2026-09-07 (part 2): wider domain coverage (media_player/cover/fan/scene, more sensor classes), v0.9

Starting point: an analysis of all 1517 entities of the real HA instance by
domain/`device_class` showed clear gaps. Asked whether to "add the five most
important per category", the user instead wanted **full coverage with no
artificial limit** ("show all entities, don't limit them") -- an automatic "top
five" selection (for battery sensors, say) cannot be meaningfully defined
without manual curation.

**Newly covered** (`qml/views/RoomsView.qml`):
- `fan`/`cover` folded into the existing `toggle` rows (they use the generic
  `<domain>.toggle` service just like `light`/`switch`). The one peculiarity:
  `cover`'s "on" equivalent is `state === "open"`, not `"on"` -- handled
  centrally in a new `isEntityOn(domain, state)` helper rather than
  distinguished at every call site.
- `media_player` as its own `kind` with a submenu (tap the name, as with
  lights/thermostats) -- a new `qml/pages/MediaPlayerDetailPage.qml` with
  play/pause/next/previous (`media_play_pause`/`_next_track`/
  `_previous_track`) and a volume slider (`volume_set`), shown only if the
  entity reports `volume_level` at all (many Chromecast/Sonos entities do not
  do so consistently). Title/artist are only displayed if `media_title`/
  `media_artist` exist (none of the 23 real media_player entities had them
  populated at test time, since nothing was playing -- coded defensively rather
  than assumed).
- `scene` as its own `kind` **without a switch**: according to the real API
  data (13 entities checked), scenes have no meaningful on/off state (the state
  is the timestamp of the last activation, e.g.
  `"2026-08-20T16:48:58...+00:00"`, or `"unknown"`) and no `toggle` service --
  only `scene.turn_on`. The UI for this: tapping the whole row activates it
  immediately (`activateScene()`), with just an "Activate" hint label on the
  right instead of a switch. The notify context menu (`menu:`) is deliberately
  not offered for `scene` -- "notify on change" makes no sense for a timestamp
  state.
- The sensor `device_class` list extended by `battery`/`energy`/`power` (with
  37/59/44 entities, the largest uncovered sensor categories in the analysis).
  `qml/views/SensorsView.qml` gained the corresponding sections
  ("Battery"/"Energy"/"Power") -- the same generic section pattern as
  temperature/humidity/pressure, no special handling needed.

**Tested**: the i486 build was installed on the emulator; since no touchscreen
is available for UI checks there, the VirtualBox window output was captured
with `import` and taps/swipes simulated against the window with `xdotool` (a
single fast mousedown→mousemove→mouseup jump registers as a flick, while a slow
multi-step movement registers as a long press -- worth remembering for future
emulator UI checks). That visually confirmed: room counts rose noticeably (e.g.
Bastelzimmer 30→57) thanks to the newly covered entities, several scene rows in
the living room correctly show name + "Activate", and scroll/expand/collapse
still work. Not a single QML `ListModel` role-type warning in the journal across
the full run with all 1517 entities (the type-locking trap known from the
climate work was avoided throughout, among other things by using `String(...)`
for all `value` assignments). Installed on the real device (aarch64) with a
clean process start in the log; full visual confirmation there was not possible
(no display access over the SSH-only connection) and therefore still pending
until the user looks himself. `sfdk check -s harbour`/`-s rpmlint` still clean
on all three architectures apart from the already-accepted `libkeepalive`
warning.

## 18. Update 2026-09-08: update domain (devices with pending updates), v0.10

Still open from the original gap analysis: the `update` domain (107 entities in
the real instance, but only 3 with `state === "on"` at the time of checking,
i.e. an update available -- most entities are "off"/current most of the time).
Asked "what does it take to show devices with pending updates", the relevant
attributes were named briefly (`installed_version`/`latest_version`/`title`,
`supported_features` bit 0 == `UpdateEntityFeature.INSTALL`) along with the
recommendation **not** to hang this per room in `RoomsView.qml` but to make it
a separate, cross-room third sub-view like `SensorsView.qml` -- updates are by
nature not interesting per room, and unfiltered they would be 107 mostly
irrelevant rows for typically a handful of real hits. The user agreed ("yes,
implement it").

**New**: `qml/views/UpdatesView.qml` -- a flat list (no sections, unlike the
sensors), filtered to `state === "on"`. Per row: the name (`title` preferred
over `friendly_name`; HA usually fills `title` on `update` entities with the
actual product name rather than the technical entity label) + a second line
with `installed_version → latest_version`, and an "Install" label on the right
(the same tap-to-activate pattern as `scene` in v0.9 -- no submenu needed for a
single install trigger). It calls `update.install`; afterwards (as with
`toggle()`/`activateScene()`) a short timer + refresh, since the service call
only confirms acceptance, not completion. Rows with `in_progress === true` show
"Installing…" instead of "Install" and are no longer tappable; entities without
the `INSTALL` feature bit are likewise not tappable (a rare case, but
`supported_features` really does vary between 5/15/27 depending on the
integration).

`FirstPage.qml`'s swipe snap logic had been hard-coded to two pages
(0/`page.width`) -- generalised to `Math.round(contentX / page.width) *
page.width`, clamped to `[0, viewRow.width - page.width]`, so that it keeps
snapping cleanly with a third sub-view (and potentially more) instead of
getting stuck between pages.

**Tested**: installed on the emulator (i486); an `xdotool` swipe to the third
page confirmed correct rendering with the instance's three real pending updates
(including two ESPHome button firmware updates). No QML role-type or reference
errors in the journal. Installed and started on the real device (aarch64) and
visually confirmed by the user ("looks good on the phone"). `sfdk check -s
harbour`/`-s rpmlint` clean on all three architectures apart from the
already-accepted `libkeepalive` warning.

## 19. Update 2026-09-08 (part 2): UI polish -- colour swatch on lights, progress bar on updates, v0.11

Asked for "a suggestion for something fancy and shiny, still minimal", several
options were put forward (domain icons, a live flash on WS updates, a colour
swatch on lights, a progress bar on updates, a cover page quick action); the
user picked the two data-driven ones -- neither needs a new API call, only
attributes that are already fetched.

**Colour swatch on lights** (`qml/views/RoomsView.qml`): a small coloured
circle between the name and the switch for `light` entities with a known
colour. Real `rgb_color` is preferred; if absent, an approximation from
`color_temp_kelvin` via the Tanner-Helland approximation (`kelvinToRgb()` -- not
an exact colour model, but good enough for a small preview dot). `null` (swatch
invisible) when the light is off or neither attribute is available -- HA reports
both as `null` while off (a known limitation, see README). `attributes` had so
far only been kept live over the WebSocket for climate/media_player rows
(`applyStateChange()`) -- now for `light` toggle rows too, so the swatch follows
external changes immediately rather than waiting for the next pull-to-refresh.

**Progress bar for running updates** (`qml/views/UpdatesView.qml`): replaces
the version line ("X → Y") with a slim, rounded bar in `Theme.highlightColor`
while `in_progress === true`. Some integrations report `update_percentage` (the
bar fills accordingly, with the percentage next to it), others do not -- there a
travelling highlight runs instead (`SequentialAnimation on x`, back and forth)
as indeterminate progress. `updatePercentage` is stored as `-1` rather than
`null`/`undefined` when unknown -- otherwise the same ListModel role-type trap as
with the `value` field in RoomsView.qml (a Number/null mix on the same role). A
new `Timer` (`progressPollTimer`, 3s, running only while `anyInProgress`) polls
during a running installation so the bar actually grows instead of freezing at
whatever the initial tap-refresh showed.

**Debugging note**: the first version of the bar sat visibly too close to the
name line (it looked like an underline rather than a second line) -- the cause
was simply too little height for the bar `Item` (`Theme.paddingMedium`, then
`Theme.fontSizeExtraSmall + Theme.paddingSmall` as an attempt, both still too
tight). Fix: item height raised to `Theme.paddingLarge`, bar thickness raised
from `Theme.paddingSmall/2` to a full `Theme.paddingSmall` (a clearly visible
"pill" rather than a hairline), AND the `ListItem` delegate's own
`contentHeight` enlarged by `Theme.paddingSmall` for `in_progress` rows so the
extra height does not collide with the next row. Only after this third
iteration did it actually look like a clean bar in the screenshot rather than a
rendering glitch.

For the visual check on the emulator, two fake rows (`in_progress: true`, one
with and one without a percentage) were temporarily inserted at the start of
`buildEntries()` (`matches.unshift(...)`) so the bar could be triggered without
a real `update.install` against the live HA instance -- a real install trigger
would have started actual device firmware updates on the user's hardware, which
was not something to risk unasked. The fake rows were removed again before
committing.

**Tested**: emulator (colour swatch with "Küche Tisch Lampe", real `rgb_color:
[255, 167, 88]`, correctly rendered as a warm orange dot; progress bar verified
with the fake test rows, see above), real device (aarch64, installs and starts
without errors, no QML errors in the log). `sfdk check -s harbour`/`-s rpmlint`
clean on all three architectures apart from the already-accepted `libkeepalive`
warning.

## 20. Update 2026-09-18: real mobile_app integration (push + device status), v0.12

User request: "rebuild the notification and device-status functionality of the
original app" -- explicitly not the existing poll-based approach (stage 3 /
option B), but the real `mobile_app` mechanisms of the official HA Companion
app: (a) HA can actively push messages to the phone (`notify.mobile_app_...`,
e.g. from automations), and (b) the phone reports its own sensors (battery
level, connection type) back to HA. Confirmed by asking before implementation
started.

**API mechanics read up front from the real `home-assistant/core` source** (not
guessed) -- `mobile_app/const.py`, `notify.py`, `push_notification.py`,
`websocket_api.py`, `webhook.py`, `http_api.py`: registration via `POST
/api/mobile_app/registrations` (bearer token like the existing REST calls);
`app_data.push_websocket_channel: true` is already enough according to
`supports_push()` in `util.py` for HA to offer a genuine
`notify.mobile_app_<device>` service, delivered over the **WebSocket connection
that already exists** (from section 8) -- no own HTTP server and no C++ bridge
object needed. The client sends `{"type":
"mobile_app/push_notification_channel", "webhook_id": ..., "support_confirm":
false}` once, and HA then delivers pushes as regular `event` messages on the
same connection. Sensor updates run separately via `POST
/api/webhook/<webhook_id>` (no bearer header needed -- the webhook ID itself is
the secret) with `register_sensor`/`update_sensor_states`.

**Device-status sensors without UPower**: SailfishOS uses `com.nokia.mce`
(`get_battery_level`/`get_charger_state`) for battery level and charging state
rather than UPower, and `net.connman` (`Manager.GetServices()`, first entry =
the active connection) for the connection type -- both verified directly against
the running SDK emulator with `dbus-send --system` (`org.freedesktop.UPower`
simply does not exist on SailfishOS) before
`qml/components/DeviceStatusProbe.qml` was written. The exact `Nemo.DBus` QML
API (`getProperty`/`call`/`typedCall`; no `plugins.qmltypes` exists for this
plugin) was verified with `strings` on the plugin `.so` in the SDK target
instead of relying on memory.

**Two real bugs found and fixed during the end-to-end test against the user's
real 1500+ entity instance** (they did not show up in the emulator alone --
debugging ran via curl straight against the real HA instance, since this
machine can reach it on the local network):

1. **`os_version` is effectively required despite being "optional" in HA's own
   schema.** Without that field, `mobile_app`'s own `async_setup_entry()`
   crashes (a direct dict access with no fallback) AFTER the `webhook_id` has
   been created but BEFORE it is registered with the generic webhook
   dispatcher. The symptom was insidious: the REST registration still reports
   success (HTTP 201 + an apparently valid `webhook_id`), but every subsequent
   call against that ID (`register_sensor`, push, even `get_config`) gets HA's
   empty-200 response for unknown webhooks forever -- the webhook dispatcher's
   generic anti-enumeration behaviour. Only found by diffing `curl` calls with
   and without `os_version`. Fix: always send a static `os_version` value (no
   native read of the real SailfishOS version -- that would need C++, and HA
   only displays the value anyway).
2. **The push channel subscription had a race condition**: it was only sent
   from the WebSocket's `auth_ok` handler, but at that point the registration
   (an asynchronous REST call in `harbour-hacontrol.qml`) was often not
   finished yet on a restart -- leaving push unsubscribed for the rest of that
   connection. Fix: a dedicated `subscribePushChannelIfReady()` function,
   additionally hooked to `webhookIdSetting`'s `onValueChanged`.

**Verified end-to-end against the real instance** (emulator, i486):
registration creates a new, clean `mobile_app` device "SailfishOS Phone" in HA
(confirmed by a WebSocket admin query: exactly one `state: "loaded"` entry, no
leftovers despite several test registration runs -- HA's config-entry dedup by
`unique_id = app_id-device_id` works as expected). `notify.send_message`
(target entity `notify.sailfishos_phone`) triggered from HA's dev tools --> the
push banner appears on the emulator immediately, confirmed by screenshot. All
three device-status sensors (`sensor.sailfishos_phone_akkustand`,
`binary_sensor.sailfishos_phone_ladt`,
`sensor.sailfishos_phone_verbindungsart`) show up with values plausible for the
emulator (no real battery --> `-1`, correctly filtered out instead of being
sent as a sensor value; `ladt: on` and `verbindungsart: ethernet` matching the
emulator setup). Not a single QML error in the journal across the whole test
session.

**Addendum, same session -- real device attached**: the aarch64 RPM was
installed on the real Jolla Phone (`192.168.2.15`). Two cross-arch traps were
confirmed again in the process (already known from sailtalerwallet, experienced
first-hand here for the first time): (1) running `sfdk build` for i486 and then
aarch64 in the same working directory (no shadow build) silently relinks the
leftover i486 `.o`/binary into the aarch64 RPM -- visible as `warning: Binaries
arch (1) not matching the package arch (2)` during the build, and leading to
`nothing provides libQt5Core.so.5` when installing on the real device (even
though that same library is obviously present there for the already-running
v0.10). Fix: `rm -f harbour-hacontrol harbour-hacontrol.o Makefile moc_*` before
every architecture switch. (2) `pkcon install-local` over `ssh -tt` produced
runaway output as documented -- the fix, as already known, is not to force a
PTY.

There was also a third, smaller trap while cleaning up old app instances:
`devel-su killall harbour-hacontrol firejail invoker` was meant to hit only this
app, but (process name collision) also terminated the user's running camera,
email and browser apps, since those run under `firejail`/`invoker` too. No data
lost, but a warning sign: never `killall` a name as generic as
`firejail`/`invoker` on a device with other apps running.

**Verified on real hardware**: registration automatically created a second,
clean `mobile_app` device (a different `deviceId` than the emulator, hence the
`_2` entity suffix in HA) with real values -- battery level actually `55`/`56`
(not `-1` as in the emulator, so the real `get_battery_level()` works), `ladt:
on` (the phone was on the USB cable at test time, correctly detected),
`verbindungsart` briefly `offline` right at the very first app start
(`GetServices()` evidently ran before ConnMan had re-sorted its service list
after the connection came up), then correctly `wifi` at the next update --
self-healing via the next ten-minute poll, not a code bug (verified with a
debug `console.log` of the raw `GetServices()` response, then removed again).
A real push (`notify.send_message` on `notify.sailfishos_phone_2`) was confirmed
by the user directly on the device ("yes"). `sfdk check -s harbour`/`-s
rpmlint` clean on all three architectures apart from the already-accepted
`libkeepalive` warning.

## 21. Update 2026-09-18 (part 2): SensorsView grouped by room, v0.50

User request: "split the sensor page by room too and make it collapsible" --
`qml/views/SensorsView.qml` had so far grouped sensors by quantity
(temperature/battery/...), not by room. Rebuilt to exactly the same pattern as
`RoomsView.qml`: `HaApi.getAreaMap()` for the room assignment,
`expandedRooms`/`toggleRoom()` for expand/collapse (rooms start collapsed), the
same header row style (▸/▾ + room name + count). A room can now contain mixed
sensor types (e.g. temperature + energy + pressure one after another in the
same room) -- the value+unit format is unchanged. The category headers
(Temperature/Battery/...) are gone.

**Swipe simulation was unreliable this session** (unlike earlier sessions) --
several attempts with the otherwise working single-jump pattern landed
inconsistently (sometimes no movement at all, sometimes two pages skipped).
Rather than trusting the code analogy to RoomsView.qml blindly,
`FirstPage.qml`'s `SilicaFlickable` briefly got a `Component.onCompleted:
contentX = page.width` so as to land directly on the sensor page, verified by
screenshot (rooms with counts, expanding works, mixed sensor types correct),
then the debug line was removed again.

Noticed thanks to a question from the user ("does every page have a title...?"):
`RoomsView.qml`'s `PageHeader` showed "HA Control" (the app name) instead of a
page title -- the only one of the three sub-views without its own title (the
sensor overview and updates already had one). Changed to "Räume".

**Version jump 0.13 → 0.50**: after asking (since a wish for "0.5" was
ambiguous -- a step back, or a typo for the running count), the user explicitly
confirmed the jump to 0.50 rather than continuing the running 0.1x numbering.

## 22. Update 2026-09-18 (part 3): credentials encrypted in Sailfish Secrets, v0.51

Goal: stop storing the HA URL and long-lived access token in plaintext in dconf
(`ConfigurationValue`) and put them into Sailfish Secrets instead -- encrypted,
tied to the device lock, with the Sailjail `Secrets` permission. The user's
instruction was explicitly "test it on the phone" -- result first: **it runs on
the real Jolla Phone**, details and evidence below.

**The first attempt, built purely in QML, turned out to be unfixable** (v0.50-3
installed on the device, journal captured via `devel-su journalctl -f`):

- `Credentials.qml:125: Error: Cannot assign QJSValue to
  Sailfish::Secrets::Secret::Identifier` -- from the JS object literal meant to
  set the identifier for `StoredSecretRequest`. The reason (read in the
  `sailfish-secrets` sources, not guessed): `Secret::Identifier` is a plain C++
  class in `lib/Secrets/secret.h` without `Q_OBJECT`/`Q_GADGET`, and
  `qml/Secrets/main.cpp` never registers it -- so it is neither constructible
  nor assignable from QML. The read path is therefore simply not usable through
  the QML API.
- `Credentials.qml:64: Error: Cannot assign int to an unregistered type` (on
  every save attempt) -- `StoreSecretRequest.secretStorageType` is an enum
  without `Q_ENUM`; even the imperative assignment from JS (documented as
  working in the file's own comment) fails.
- Cross-check: no match for `harbour-hacontrol` in
  `~/.local/share/system/privileged/Secrets/.../secrets.db`, WAL timestamps
  unchanged -- nothing had been stored. After manual entry the app was
  configured in RAM only (a restart would have lost the values).

**Implemented: a C++ wrapper** (`src/credentials.{h,cpp}`, the first native
object in this project -- the README had explicitly advertised "no C++ bridge
object" until then):

- A `Credentials : QObject` class with `baseUrl`/`token`/`loaded`/`lastError`/
  `saveBusy`/`lastSaveOk` as properties plus `save(url, token)`/`reload()`; set
  as the context property `Credentials` in `main()`, which leaves every QML
  call site unchanged (only the `import "../lib"` lines disappeared). The QML
  singleton `qml/lib/Credentials.qml` and its `qmldir` were deleted -- which
  also got rid of the build warning `qmldeps: no valid module definition`.
- Requests run asynchronously (`statusChanged`), never `waitForFinished()` on
  the UI thread. Saving is an upsert: first `DeleteSecretRequest`, then
  `StoreSecretRequest` (otherwise `SecretAlreadyExistsError`).
- **Plugin choice at runtime instead of hardcoded**: `PluginInfoRequest` asks
  the daemon at startup which plugins it knows. Two traps verified on the
  device: (1) `StandaloneDeviceLockSecret` with the *encrypted storage* plugin
  failed -- `No such storage plugin exists:
  org.sailfishos.secrets.plugin.encryptedstorage.sqlcipher`, even though the
  `.so` is installed and the daemon does list the plugin under
  `encryptedStoragePlugins`; it just does not accept it as a *storage* plugin.
  (2) Without `encryptionPluginName` the store fails with `No such encryption
  plugin exists: ` (empty name). The working combination on the Jolla Phone:
  `org.sailfishos.secrets.plugin.storage.sqlite` +
  `org.sailfishos.secrets.plugin.encryption.openssl`.
- **One-time migration** (`qml/harbour-hacontrol.qml`): existing plaintext
  values are copied into Secrets automatically at startup, after which the
  dconf copies are cleared -- but **only after a confirmed store**
  (`saveBusy`/`lastSaveOk`). The first version deleted unconditionally and
  would have destroyed the credentials if the store failed (which is exactly
  what happened on the first test run; the values were restored from the backup
  with `dconf load` for the rest of the test).
- SettingsPage writes on focus loss / page change rather than on every
  keystroke, only when both fields are complete and have changed, and displays
  the daemon's `lastError`.

**Verified on the real Jolla Phone (aarch64, 192.168.2.15)**:

- Store + migration: journal shows `Credentials: stored "baseUrl"` / `"token"`,
  after which `baseUrl`/`token` in dconf are empty.
- Persistence across an app restart: `Credentials: loaded -- baseUrl 17 chars,
  token 183 chars` -- without re-entering anything.
- A real connection: the app process holds an ESTABLISHED TLS connection to the
  resolved address of the configured host -- so the values loaded from Secrets
  really are used against the real instance.
- No more QML errors in the journal (the two above are gone).
- **Harbour**: `sfdk check -s harbour` passes cleanly once `Requires:
  libsailfishsecrets` was removed -- the validator rejects the plain package
  name ("Dependency not allowed"), while the soname dependency rpmbuild
  generates automatically, `libsailfishsecrets.so.0()(64bit)` (which is on
  Harbour's allowed APIs list), is accepted. Do not write the soname by hand --
  that is exactly what broke the real `pkcon` installation for `libkeepalive`
  back in v0.7. `-s rpmlint` still only reports the accepted
  `explicit-lib-dependency libkeepalive`.

**Addendum, same session -- pull-down refresh + device sensors (0.51-2)**: user
requests "pull-down refresh should refresh all pages" plus "test again whether
home gets sensor data from the phone".

- The three sub-views sit side by side at the same time and load their own
  data; refreshing only the visible one left the others with stale data. Each
  view now has a `refreshRequested()` signal, `FirstPage.qml` bundles that in
  `refreshAll()` and calls all three `refresh()` functions.
- **Finding on the device sensors**: in HA, `sensor.sailfishos_phone_*_2` had
  been stale for hours even though the app was running -- the ten-minute
  `BackgroundJob` does not fire while the app is in the foreground (and up to
  then the sensors were only reported from that job). So the app now also
  reports device status on every app start (`onLoadedChanged`) and on every
  pull-down refresh (`updateDeviceSensors()`), with a journal log line
  (`DeviceSensors: 3 Sensoren an HA gemeldet`).
- **An HA characteristic that confused the diagnosis at first**: HA's
  `mobile_app` flow only writes a sensor value when it actually changes -- so
  `last_updated` stays put even when the app reports successfully
  (`{"battery_level":{"success":true},...}`). Demonstrated by a cross-check:
  the token webhook was fed a battery level of `91` from outside (HA showed
  91), then the app was restarted -- HA moved to `90` with a fresh
  `last_updated`, i.e. the phone's real value
  (`/sys/class/power_supply/battery/capacity`). Delivery phone → HA is
  therefore demonstrated, not merely claimed.
- Checked on hardware: 0.51-2 installed, journal free of QML errors,
  `Credentials: loaded -- baseUrl 17 chars, token 183 chars`, twice
  `DeviceSensors: 3 Sensoren an HA gemeldet`. The pull-down itself needs a tap
  on the device (the touchscreen could not be operated at the time) -- still to
  be confirmed by the user.

**Still open**: emulator test (i486) and the `armv7hl` build/check for v0.51
(only aarch64 was built and hardware-tested so far); confirmation of the
pull-down refresh by a tap on the device; the credentials backup
`~/sailhacontrol-credentials-backup.txt` can be deleted after the migration.

## 23. Update 2026-09-18 (part 4): cover reworked per the UI guidelines, three bugs found on the way, v0.52

The starting point was a review of the app against the official UI guidelines
(`docs.sailfishos.org/Develop/Apps/UI/`). Most of it was already compliant:
every sub-view has its own `PageHeader` and a pull-down menu with only two
entries (the guideline recommends fewer than five), the horizontal page change
carries Silica's own gesture hint via `HorizontalScrollDecorator`, and the
detail pages are real stacked `Page`s rather than dialogs.

The one real gap was `qml/cover/CoverPage.qml`: a static "HA Control" label,
even though covers are supposed to show "key information" and offer "cover
actions for quick tasks without opening apps".

**Implemented:**
- The cover now shows how many lights are on ("4 Lichter an" / "Alle Lichter
  aus").
- A `CoverAction` toggles the light last operated from the app, without opening
  it. The icon is `icon-cover-favorite` -- the stock theme has no bulb/power
  icon (checked in the build target's icon list via `sfdk tools exec`, not
  guessed).
- Both are kept up to date by `RoomsView.qml` through three
  `ConfigurationValue`s (`coverLightsOnCount`, `coverLastLightId`,
  `coverLastLightName`), the same pattern as `webhookIdSetting`. That way the
  cover needs no HA query of its own while the app is in the background.

**Bug 1 -- lists stayed empty until a manual pull-down.** Noticed during
testing; it had been there for a while but was dismissed as habit ("you just
always have to refresh once"). Cause: `Component.onCompleted: refresh()` fires
in all three sub-views before `Credentials`' asynchronous Sailfish Secrets
request has finished -- `baseUrl`/`token` are still empty then, the attempt
comes to nothing (SensorsView/UpdatesView even visibly showed "not configured
yet"), and nothing retried afterwards. Fix: RoomsView additionally reacts to
`onConfiguredChanged`, SensorsView/UpdatesView to `Credentials`'
`onBaseUrlChanged`/`onTokenChanged`.

**Bug 2 -- ANR on refresh (self-inflicted).** The first version of the
lights-on count did a full scan over `entriesModel` -- once per refresh and
additionally on **every single** `light` `state_changed` event over the
WebSocket. On the real instance (~1500 entities, 700+ rows in the model) and a
phone under heavy load (Android App Support with several resident apps,
`loadavg` > 15) that blocked the `QSGRenderThread` permanently: the app ran
into a genuine ANR ("HA Control reagiert nicht"), not a crash. Demonstrated by
sampling `/proc/<pid>/task/<tid>/stat` -- the render thread accumulated ~8-10
CPU ticks per second continuously instead of dropping back to idle. Fix: the
count is now computed in `buildEntries()` during the pass that already iterates
the raw `states` array, and live updates only adjust it incrementally (+1/-1).

**Bug 3 -- page changes too twitchy, and the first fix was worse.** A slightly
firmer flick let the `SilicaFlickable` coast freely; the snap logic then landed
on whatever page was nearest and skipped one (Rooms -> straight to Updates).
The snap target is now clamped to +/-1 page relative to where the gesture
started. The first attempt recorded the start page in `onMovementStarted` --
but that also fires for the **programmatic** snap animation, so the start page
was re-recorded mid-animation, the clamped target shifted, the next animation
started, and so on: an endless loop, the render thread permanently busy, an ANR
about a second after startup and before any data had loaded. Rule of thumb for
future flickables: snap logic belongs on `onDragStarted` plus a `userGesture`
flag, never on the movement signals alone.

**Newly learned: UI tests on the real device are possible.** The assumption so
far was "SSH only, no display access, visual checks in the emulator only". In
fact touch events can be injected straight into the touchscreen: `hyn_ts` is
`/dev/input/event5`, its ABS range matches the display resolution 1:1
(1032x2272); the `evemu` tools are missing, but `python3` is there and can
write raw `struct input_event`s (type-B multitouch: `ABS_MT_SLOT`,
`ABS_MT_TRACKING_ID`, `ABS_MT_POSITION_X/Y`, `BTN_TOUCH`, `SYN_REPORT`; always
put the release in a `finally`, otherwise the touchscreen stays blocked for the
real finger). That is how v0.52 was checked on hardware rather than only in the
emulator: all three pages load their data on startup by themselves (rooms,
sensor overview, updates overview, each with real data), a firm flick moves
exactly one page, the render thread stays idle (1 CPU tick over 3 seconds), and
the cover shows "4 Lichter an" live.

**Still open**: the cover's star only appears once a light switch has been
tapped in the app itself -- `coverLastLightId` is empty until then. That is by
design ("last light operated"), but it was confusing on the first test.

## 24. Update 2026-09-19: Definition-of-Done review -- empty states and remorse, v0.53

The UI guide itself gives little away on detail questions; the real yardstick
is its sub-page **`docs.sailfishos.org/Develop/Apps/UI/Definition_of_Done/`** --
a checklist covering pixel accuracy, performance, deriving from the theme,
translation hooks, and two points that were concretely open here: "no empty
views, placeholder data, or temporary development elements remain visible" and
"users have clear recovery options for error scenarios".

**Empty states (`ViewPlaceholder`).** The content was covered ("Alle Geräte
sind aktuell.", "Noch nicht konfiguriert -- ...") but rendered as plain
left-aligned `Label`s in the list header instead of Silica's `ViewPlaceholder`.
Each of the three sub-views now has three placeholders -- not configured, no
connection, empty result -- centred in the upper third, and their `hintText`
names the way out (Settings, or pull down to refresh), which also covers the
checklist's recovery point.

**A translation trap defused along the way.** `SensorsView` and `UpdatesView`
distinguished "not configured yet" from a real error by comparing `errorText`
against the translated message text (`errorText.indexOf(qsTr("Noch nicht
konfiguriert")) === 0`, purely to pick the text colour). That would have
silently stopped working the first time the UI was actually translated. Both
now carry the same `configured` property as `RoomsView`, `errorText` is
reserved for real errors, and the startup refresh hangs off
`onConfiguredChanged` as it does there.

**Remorse before a firmware update.** Tapping a row in the updates overview
called `update.install` immediately. On real hardware that cannot be taken back
-- while testing with injected touch events it was the single most dangerous
spot on the screen. The row now uses `ListItem.remorseAction()`: a five-second
window in which a tap cancels the request. More important than the remorse
itself is **what** gets remembered: not the row index but the `entityId`.
During those five seconds a refresh (pull-down, `progressPollTimer`, WebSocket
update) can rebuild the model, and a stale index might afterwards have sent the
firmware update to an entirely different device.

**What came up while verifying, and is still open**: if Home Assistant is
unreachable, the `BusyIndicator` keeps spinning forever -- `errorText` stays
empty because the `XMLHttpRequest`s in `HaApi.js` have no timeout and neither
the success nor the error callback ever fires. So the new "no connection"
placeholder does not appear in exactly the situation it was written for. A
request timeout is the next sensible step; only then does the placeholder
become effective.

Deliberately **not** addressed (the user's decision): the UI still mixes German
and English labels ("Settings"/"Refresh"/"Live" next to "Räume"/
"Sensor-Übersicht"), and the `.ts` files stay without translations.

## 25. Update 2026-09-19 (part 2): request timeouts and lazy per-page loading, v0.54

The user reported "the version on the phone hangs on startup again". Two
distinct things turned out to look identical from the outside, and only one of
them was a code problem.

**The red herring: an orphaned firejail wrapper.** Killing the app binary
leaves its `firejail` parent behind, and Lipstick keeps that dead instance's
"not responding" dialog on screen -- covering the freshly started, perfectly
healthy instance. This happened repeatedly during this session's test cycles
and looked exactly like a new regression each time. The reliable way to tell
them apart is to sample `/proc/<pid>/task/<tid>/stat` for the *new* process: a
real hang keeps `QSGRenderThread` accumulating CPU ticks non-stop, whereas a
merely covered instance shows both the main and render threads idle with their
counters frozen. The cure is to kill the orphaned wrapper by its exact PID as
well; never by a generic name like `firejail`, which would take down every
sandboxed app on the device.

**The real defect: requests with no time limit.** When Home Assistant is
unreachable, QML's `XMLHttpRequest` fires neither the success nor the error
callback until the system TCP timeout eventually gives up minutes later. The
BusyIndicator then span forever, the app looked frozen -- and the "no
connection" placeholder added in v0.53 never appeared, because `errorText`
stayed empty. Whether Qt's QML XHR supports `timeout`/`ontimeout` could not be
established: `strings` on `libQt5Qml.so.5` does not surface even `responseText`,
and `qmlscene` in the emulator aborts under both `-platform minimal` and
`offscreen`. Rather than guess, the limit is a plain QML `Timer` (15s) per
view, restarted on every load attempt and stopped by every callback --
independent of whatever the XHR implementation does. A late response still
overwrites the error state, so it heals itself.

A WebSocket (re)connect now also triggers a reload, because the socket only
carries deltas, not structure -- without it the view kept showing "no
connection" long after HA was reachable again. That reload is debounced by one
second: after an outage several pending reconnects come through at once, and
ungated this ran `refreshAll()` three times in the same second (measured),
i.e. three `getStates` over ~1500 entities -- precisely the kind of load spike
that caused the earlier ANR.

**Startup made much lighter.** All three sub-views used to load at startup,
each fetching the complete entity list, parsing it and building its own model
-- three times ~1500 entities in parallel on the real instance. On a phone
already under load (Android App Support, `loadavg` around 14) that was the
actual reason startup crawled. Each view now loads the first time it becomes
the current page; pull-down refresh still refreshes every page that has
actually been opened. Measured with a temporary log line per load: startup
triggers one load instead of three, the first swipe adds the sensor page, the
second the updates page -- each exactly once.

One subtlety showed up while verifying this: deriving "which page is current"
continuously from `contentX` made a firm flick briefly overshoot the target
page, so the page *after* the one being swiped to started loading as well
(measured: one swipe to sensors also loaded updates). The current page is
therefore set when the snap target is decided, not while the view is still
moving.

**Test method worth keeping**: the unreachable-HA case was reproduced in the
emulator with `sudo iptables -I OUTPUT -d <HA-IP> -j DROP` (the target address
read out of `/proc/<pid>/net/tcp` of the app process, hex little-endian), always
paired with a `nohup sh -c 'sleep 150; iptables -D ...' &` safety net so a
forgotten rule cannot linger. The placeholder appears after 15s instead of a
spinning indicator, and the room list returns by itself once the rule is
dropped.

## 26. Update 2026-11-04: English source strings and a translation workflow, v0.55

Prompted by two requests on the Sailfish OS forum. Half of the `qsTr()` source
strings were German and `harbour-hacontrol-de.ts` was an empty template, so the
UI was a mix of both languages whatever the phone's locale. All source strings
are now English and the German file is complete. The cover's "lights on" text
uses `%n` plural forms, and the save error uses `%1` instead of concatenation so
other languages can reorder it. `harbour-hacontrol.pro` picks up every
`translations/harbour-hacontrol-*.ts` via `$$files()`, so a contributor only
adds a file; `TRANSLATING.md` and `translations/new-language.sh` describe the
steps. The default device name "SailfishOS Phone" stays untranslated in German
on purpose: it is the name registered in Home Assistant.

## 27. Update 2026-11-06: favorites, search, more entity types, sensor history, cover action, remote access, v0.56

Six features, built in parallel on separate branches and merged afterwards.

- **Favorites** (`RoomsView.qml`): stored as a comma-separated list in
  `/apps/harbour-hacontrol/favoriteEntities`, like `watchedEntities`. Favorite
  rows are *copies* in a "Favorites" group at index 0 (`favGroup: true`), so
  `applyStateChange()` and `toggleWatch()` now update every row with a given
  entity ID instead of stopping at the first match. The cover's lights-on
  counter is still adjusted once per event (`countedLight`). Adding/removing a
  favorite edits the model in place on `onDelayedClick`, because removing can
  delete the very row whose context menu was open.
- **Search**: a `SearchField` in the list header, 250 ms debounce, one pass
  over the model per query that fills lookup maps; delegates only look
  themselves up. `expandedRooms` is never touched, so clearing the field
  restores the previous expand/collapse state.
- **Entity types**: `input_boolean` joins `toggleDomains`; `script`, `button`
  and `input_button` reuse the scene row (Run / Press, "Done" feedback for 2 s).
  Locks are a new kind: locking is immediate, unlock/open go through
  `remorseAction` with the entity ID captured (same reasoning as the install
  remorse in section 24). Locks deliberately get no "Notify on change": the
  notification's Toggle action would unlock without confirmation, and `lock`
  has no `toggle` service. Covers with SET_POSITION or `current_position` open
  `CoverDetailPage.qml` (slider + Open/Stop/Close by feature bits); the page
  follows live updates through a new `liveStateReceived` signal.
- **Sensor history** (`SensorHistoryPage.qml`): `/api/history/period/<start>`
  with explicit `end_time` (without it HA ends at start + 1 day, which cut the
  7-day view), `minimal_response` and `no_attributes`. Drawn once per data set
  on a `Canvas`; points in the same pixel column collapse into a min/max stroke,
  non-numeric states break the line. Timestamps are parsed by regex because
  Qt 5.6's `Date.parse` is not trusted with microseconds and `+00:00`.
- **Cover action** (`CoverSettingsPage.qml`): target stored in
  `coverTargetId` / `coverTargetName` / `coverTargetDomain`; empty means the old
  "last used light" behavior. Scenes/scripts run with `icon-cover-play`,
  lights/switches toggle. The cover still never polls HA itself.
- **Remote access** (`src/credentials.*`): the external URL is a third Sailfish
  secret (`harbour-hacontrol-externalUrl`); data stored by v0.55 has none and
  loads unchanged. `Credentials.baseUrl` now returns the *effective* URL and
  emits `baseUrlChanged` on a switch, so no call site changed; the WebSocket
  reconnects on that signal. In Auto mode a probe (`GET <internal>/api/` with
  the token, 3 s, only HTTP 200 counts) decides; it runs after loading, on
  save, on mode change, on network changes (`QNetworkConfigurationManager`,
  debounced), on a WebSocket error and on the 15 s request timeout, and every
  60 s while on the external URL to switch back. The mode (Auto / internal
  only / external only) is not secret and lives in dconf.

### 27b. Same release: cameras, to-do lists, multiple instances

- **Cameras** (`CameraPage.qml`): QML `Image` can't send an Authorization
  header, so stills come from `/api/camera_proxy/<id>?token=<access_token>`
  using the entity's rotating `access_token` attribute, followed live via
  `liveStateReceived`; on a load error the state is fetched once more
  (`HaApi.getState`) and retried. Two `Image`s double-buffer the refresh so it
  doesn't flicker; the timer only runs while the page is active and the app is
  in the foreground. Qt logs the full URL when an image load fails, so
  `main()` installs a message handler that redacts `token=` values before
  anything reaches the journal.
- **To-do lists** (`TodoListsPage.qml`, `TodoListPage.qml`): items via
  `todo.get_items` with `?return_response` (`HaApi.callServiceWithResponse`),
  changes via `todo.update_item` / `add_item` / `remove_item` /
  `remove_completed_items`. Checking is optimistic with rollback. A live state
  change of the list entity (open count) triggers a debounced silent reload
  that leaves the model alone when nothing changed.
- **Profiles** (`src/credentials.*`): profile 0 keeps the existing secret names
  and dconf keys, so upgrades need nothing re-entered; further profiles use
  `-p<id>` secret suffixes and `/apps/harbour-hacontrol/profiles/<id>/` for
  per-instance dconf keys (`Credentials.settingsPrefix`). Ids are never reused.
  The profile list lives in dconf as JSON and is written by QML, so the C++
  side needs no extra library. Switching clears URL/token first so the change
  signals always fire, then loads the new profile's secrets and probes; views
  drop late answers from the previous instance by comparing the profile id
  captured at request time. The background poll only covers the active
  instance.
- Verified on the emulator against the real instance: upgrade from v0.56 data
  keeps the configuration (it becomes profile 0 "Home"), cameras, to-do lists,
  sensor history and the new Settings page all work with real data.

### 27c. Same release: Assist, more device sensors, alarm/vacuum/media, weather, two cover buttons, notification actions

- **Assist** (`AssistPage.qml`): `POST /api/conversation/process` with the
  phone's language (only if it looks like an ISO code, so a "C" locale falls
  back to HA's default) and the `conversation_id` of the previous answer while
  the page is open. Agent selection is left out: HA only lists agents over the
  WebSocket. Silica's ApplicationWindow already shrinks the page while the
  keyboard is open, so the input field simply anchors to the page bottom.
- **Device sensors**: Wi-Fi SSID/strength come from connman's `GetServices`
  through `Nemo.DBus` (Harbour-allowed; the Connman QML modules are not), which
  the Internet permission already covers. Free storage via `QStorageInfo` in a
  tiny `DeviceInfo` context object. Location is opt-in per instance
  (`QtPositioning 5.4`, sailjail `Location` permission), one fix ≤ 500 m per
  report, never continuous. New sensors are registered once per session per
  webhook id, so existing installs pick them up without re-registering.
- **Alarm panels / vacuums**: new row kinds and detail pages, buttons by
  `supported_features`. The alarm code lives only in a page property and is
  cleared before every call. Alarms may be watched, but their notification
  gets no Toggle button; the D-Bus `toggleEntity` endpoint also checks an
  allowlist (`toggleNotificationDomains`), because any process in the session
  can call it and must never be able to disarm an alarm or open a lock.
- **Media players**: source, mute, power, artwork (relative `entity_picture`
  prefixed with the effective base URL), inline play/pause in the row.
- **Weather**: `weather.get_forecasts` (daily, or twice_daily day parts) with
  fallback to `attributes.forecast`; the entity is chosen in Settings or by
  tapping the card (same per-instance keys, the view follows `valueChanged`).
  The cover's weather line is written by SensorsView; the cover never polls.
- **Two cover buttons**: `CoverAction` has no `visible`, so CoverPage keeps
  three `CoverActionList`s (first only, second only, both) and enables one.
  The picker became a generic `EntityPickerPage.qml`.
- **Notification actions** (`PushNotifications.qml`): `data.actions` become
  remote actions on the existing `org.example.hacontrol` D-Bus path and fire
  `mobile_app_notification_action` through the webhook of the instance the
  push came from (its URLs read from Secrets if it is not the active one;
  internal first, external only if there was no answer at all, so an event is
  never sent twice). A nonce per notification, remembered in dconf, prevents
  double execution. `tag` replacement finds the old notification through
  `Notification.notifications()`.
- **D-Bus activation**: Harbour rejects own `.service` files, but accepts
  `ExecDBus=harbour-hacontrol` in `[X-Sailjail]`; sailjaild then writes the
  activation file itself (with invoker and `--single-instance`). Calls that
  arrive before Secrets has loaded wait in `whenLoaded()`.
- Testing note: on the emulator, app output goes to the journal
  (`journalctl | grep harbour-hacontrol[`), not to stdout/stderr of a process
  started over SSH -- an empty redirected log does not mean "no warnings".

## 28. Update 2026-11-06 (part 2): UI pass, v0.57

After v0.56 added about twenty features in two days, a pass on consistency
rather than more functions. Four parallel branches, merged and checked on the
emulator in a dark (extrasail) and a light (glacial, `darkonlight`) ambience.

- **Settings** became an overview (instance + three navigation rows with a
  one-line summary) and sub-pages `ConnectionSettingsPage.qml`,
  `DeviceSettingsPage.qml` and the existing `CoverSettingsPage.qml` (now
  "Cover & weather", with the weather picker). `profileScopedSettings` stays
  in one place on the overview. The long-standing
  `TextField.qml:87: Binding loop detected for property "width"` came from
  TextFields that already had text while being created (Qt's implicitWidth
  getter re-entering the layout); text is now assigned in
  `Component.onCompleted` and kept in sync via `Connections`.
- **Room list**: `RoomSectionHeader.qml` (loaded only for header rows, the
  flat single-ListModel design stays) and a leading icon per entity. The
  domain -> icon mapping lives in `qml/lib/EntityIcons.js` and is shared with
  the detail pages. It was chosen by pulling the actual images out of the
  emulator's theme (`/usr/share/themes/sailfish-default/silica/z1.0/
  icons-monochrome`) into a contact sheet -- several first picks only matched
  by name (a flashlight for lights, a battery-like bolt for switches, a bell
  that reads as an alarm clock). Idle icons use `secondaryColor`, active ones
  `highlightColor`, errors `errorColor`. A toggle row subtracted the hidden
  "notifies" label and colour swatch from the name width, which cut names
  after ~20 characters -- only visible items are subtracted now.
- **To-do**: completed items fold to height 0 under "Completed (n)". As a
  ListView `section.delegate` that header was drawn twice by Qt 5.6 once the
  rows around it had height 0, so it is now part of the first completed row's
  delegate. The expanded state is kept per list for the session
  (`qml/lib/TodoUiState.js`).
- **Page dots** in `FirstPage.qml` follow `contentX`, jump on tap and fade
  out four seconds after start or a page change so they don't cover the
  bottom row.
- **Detail pages**: shared `DetailPageHeader`, `DetailStatusBlock`,
  `DetailErrorLabel`, `ActionButtonGrid` (actions passed as data; Qt 5.6
  drops functions from array models, so the Repeater counts) and
  `ServiceCaller` (busy state, 15 s timeout, never logs service data).
- The attributes role only ever receives plain objects (`plainAttributes()`),
  after a one-off `Can't assign to existing role 'attributes' of different
  type [List -> VariantMap]` warning that could not be reproduced.
- **Found on the real device**: the first v0.57 build froze at startup on the
  Jolla Phone (lipstick "not responding"; main thread in `futex_wait`, render
  thread busy in GPU polls) but ran fine on the emulator. Bisected on the
  phone over Tailscale: v0.56 was fine; removing the page dots'
  `Behavior on opacity { FadeAnimator {} }` from the installed QML fixed it.
  It is a `NumberAnimation` now. Lesson: render-thread animators need a test
  on the Mali device before release. The same build also confirmed on the
  device that v0.55 credentials survive the upgrade (profile 0, nothing
  re-entered) and that sailjaild writes the `ExecDBus` activation file.

## 29. Update 2026-11-06 (part 3): the startup freeze, properly; faster rooms, v0.58

**Correction to section 28**: the FadeAnimator was not the cause. The freeze
is intermittent -- repeated launches on the phone (a script starting the app
over SSH via `invoker`, sampling the main thread's ticks and `wchan`) showed
the released v0.57 hanging in two of five starts, with the threaded and with
the basic render loop alike, so the earlier "fixed by removing the animator"
result was luck. `gdb -p` on a hung instance (gdb is installed on the device)
gave the real picture:

- main thread: `QBasicMutex::lockInternal()` inside libQt5Network, entered
  from a signal emission;
- "Qt HTTP thread": `QSemaphore::acquire()` (a blocking queued call into the
  main thread) under `QSslSocket::preSharedKeyAuthenticationRequired()`,
  called from libssl during a handshake.

The user's base URL is https. Qt 5.6 predates TLS 1.3; with the device's
OpenSSL 1.1.1 every TLS 1.3 handshake runs through Qt's PSK client callback.
The HTTP thread's handshake waits on the main thread, the main thread's own
handshake (the `wss://` WebSocket) waits on a lock the HTTP thread holds.
`main()` now sets a default `QSslConfiguration` with `TlsV1_2` and no PSK
cipher suites, so the callback is never invoked. 16 launches in a row
afterwards: no hang, no "not responding". This probably also explains the
occasional "not responding" seen around v0.54, which back then was put down
to load alone.

On the way, `QNetworkConfigurationManager` (added in v0.56 for automatic
URL switching) was removed: its first backtrace also showed the main thread
in a libQt5Network mutex, and it's not needed -- the URL choice is re-checked
when the app comes to the foreground (`Credentials.networkMayHaveChanged()`
from `Qt.application.state`), on WebSocket errors, request timeouts and every
60 s while on the external URL.

**Room toggles**: collapsed rows have height 0, so the ListView instantiates
a delegate for each of them (~520 on the real instance) and rebuilds hundreds
of them whenever a room opens or closes. Measured on the phone: ~1.6 s of
main-thread time per toggle. Row content now lives in a `Loader` that is only
active while the row is shown; hidden rows are empty `ListItem`s. ~0.43 s per
toggle afterwards. Keeping only visible rows in the model would be the next
step if that is still too slow.
