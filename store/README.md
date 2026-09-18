# Jolla Store listing assets

Prepared for a Harbour submission (account exists; the actual submission via the harbour.jolla.com web UI is done manually, not automated here). Store metadata (description, screenshots) is edited separately from the app binary on the Harbour "application edit page" and doesn't require a new package upload or re-QA once the binary itself is accepted.

Field-by-field, matching the actual submission form:

## Title
`HA Control` (10 characters -- well under the 30-char limit, no truncation risk).

## Details -> Description
`description-en.txt` / `description-de.txt` (2013 / 2233 characters, well under the 4000-char limit, updated for v0.50's full feature set). Deliberately doesn't repeat the app name (already the Title field) or the GitHub link (already the Open source project URL field) -- pure body text only, no duplication of what the form already captures elsewhere. Add German as a second language via "+ Add a language" in the form if a German listing is wanted alongside English.

## Details -> Summary
`summary-en.txt` / `summary-de.txt` (139 / 142 characters, under the 200-char limit).

## Details -> Recent changes
Not prepared -- this is meant for update announcements, and this would be the first submission. See `KONZEPT.md`'s dated update log for the full history if release notes are wanted later.

## Categorization -> Category
Not prepared -- the form's dropdown options weren't available to check against, so pick whatever fits best there directly (e.g. Utilities/Tools/Smart Home, depending on what's actually offered).

## Binaries
`../RPMS/harbour-hacontrol-0.50-1.aarch64.rpm` -- covers current 64-bit phones, verified on real hardware (including the v0.50 mobile_app push/device-status feature). `i486` is emulator-only, not for submission. `armv7hl` also builds and passes Harbour validation but has never been tested on real armv7hl hardware (see README.md's Known limitations) -- upload it too only if multi-arch is wanted despite that.

## Compatibility -> Device type
Phone (not Tablet -- never tested on a tablet form factor).

## Visual assets -> Icon
`icon-172x172.png` (copy of `../icons/172x172/harbour-hacontrol.png`, matches the form's 172x172px requirement exactly).

## Visual assets -> Screenshots
Four PNGs, refreshed for v0.50 (previous three, including the v0.7-era light detail shot, were replaced):

- `screenshots/01-rooms.png` -- room list, all collapsed. 1080x2378px, real device (Jolla Phone, aarch64), native 1032x2272 upscaled ~4.7% to clear the form's "at least 1080px wide" requirement (the phone's native width falls just short of 1080).
- `screenshots/02-rooms-expanded.png` -- Schlafzimmer expanded, showing toggle switches, the fan/switch rows, and the color swatch next to two on lights ("Licht Gabi"/"Licht Sili"). Same real device, same upscale.
- `screenshots/03-sensors-by-room.png` -- the sensor overview's new (v0.50) room-grouping, Keller expanded showing mixed sensor types (temperature, energy, power, humidity, pressure) together. Taken on the SDK emulator (720x1600 native, via `org.nemomobile.lipstick`'s `saveScreenshot` D-Bus method for a true native-resolution capture rather than a cropped window grab) and upscaled ~50% to 1080x2400 -- real-device capture wasn't usable for this specific state (see note below).
- `screenshots/04-settings.png` -- the Settings page's new "Home-Assistant-Geräteregistrierung" section (device name field + re-register button), the visible surface of the v0.50 mobile_app push/device-status feature. Same emulator method as 03.

Reaching specific in-app states (an expanded room, the Settings page) for a screenshot needs either touch input or a brief, reverted debug tweak to the QML (e.g. a `Component.onCompleted` jump or a delayed `Timer` triggering the state) since there's no scripted UI-automation harness for this app. On the real device this hit Lipstick's ANR ("application not responding") watchdog when combined with the device's chronically high background load from Android App Support (~14 load average from resident Android app processes) -- not a bug in the app itself (the process was idle/sleeping, not spinning), but real enough that it made repeated real-device state changes unreliable this session. The emulator has no such load and was used instead for shots 03/04; shots 01/02 (the app's actual startup state, no debug tweak needed) came from the real device without issue.

These show the maintainer's real Home Assistant instance (real room and device/person names, e.g. "Lars", "Licht Gabi") -- confirmed acceptable to publish as-is rather than staging anonymized/demo data in earlier rounds; unchanged policy, not re-confirmed for this specific v0.50 batch.

## Visual assets -> Cover image
Not prepared (optional field, 1080x540px). Could be generated in the same visual style as the app icon (navy-to-HA-blue gradient) if wanted later.

## Contact details -> Email
Not filled in here -- this goes to Jolla directly tied to the submitter's account, fill in manually.

## Contact details -> Open source project URL
`https://github.com/silly82/sailhacontrol`

## Publish settings -> Message to QA
Nothing unusual to flag -- the app needs a reachable local Home Assistant instance with a Long-Lived Access Token to actually show data (see README.md's Setup section); without one it just shows the "not configured yet" hint, which is expected and not a bug. As of v0.50, a configured instance also gets a `mobile_app` device registration (visible in HA under Settings -> Devices & Services) and three extra sensor entities reporting the phone's battery/connection status back -- this is intentional (see README.md's feature list), not a leak or unexpected network call.

## Still needed for an actual submission (out of scope here)

Deciding whether this app -- built for one person's private local Home Assistant instance -- makes sense as a public Store listing at all, versus staying a GitHub-releases-only project. That's a judgment call for the maintainer, not something to default into.
