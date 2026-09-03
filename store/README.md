# Jolla Store listing assets

Prepared for a Harbour submission (account exists; the actual submission via the harbour.jolla.com web UI is done manually, not automated here). Store metadata (description, screenshots) is edited separately from the app binary on the Harbour "application edit page" and doesn't require a new package upload or re-QA once the binary itself is accepted.

Field-by-field, matching the actual submission form:

## Title
`HA Control` (10 characters -- well under the 30-char limit, no truncation risk).

## Details -> Description
`description-en.txt` / `description-de.txt` (1209 / 1294 characters, well under the 4000-char limit). Deliberately doesn't repeat the app name (already the Title field) or the GitHub link (already the Open source project URL field) -- pure body text only, no duplication of what the form already captures elsewhere. Add German as a second language via "+ Add a language" in the form if a German listing is wanted alongside English.

## Details -> Summary
`summary-en.txt` / `summary-de.txt` (125 / 134 characters, under the 200-char limit).

## Details -> Recent changes
Not prepared -- this is meant for update announcements, and this would be the first submission. See `KONZEPT.md`'s dated update log for the full history if release notes are wanted later.

## Categorization -> Category
Not prepared -- the form's dropdown options weren't available to check against, so pick whatever fits best there directly (e.g. Utilities/Tools/Smart Home, depending on what's actually offered).

## Binaries
`../RPMS/harbour-hacontrol-0.7-1.aarch64.rpm` -- covers current 64-bit phones, the only architecture actually verified on real hardware. `armv7hl` also builds and passes Harbour validation but has never been tested on real armv7hl hardware (see README.md's Known limitations) -- upload it too only if multi-arch is wanted despite that.

## Compatibility -> Device type
Phone (not Tablet -- never tested on a tablet form factor).

## Visual assets -> Icon
`icon-172x172.png` (copy of `../icons/172x172/harbour-hacontrol.png`, matches the form's 172x172px requirement exactly).

## Visual assets -> Screenshots
`screenshots/01-rooms.png`, `02-sensors.png`, `03-light-detail.png` -- three PNGs, 1080x2378px. Taken as real screenshots on the real device (1032x2272 native) and upscaled ~4.7% to clear the form's "at least 1080px wide" requirement, since the phone's native width falls just short of 1080. Show the room list (collapsed), the cross-room sensor overview, and the light detail controls (brightness/color-temperature sliders + color picker button) in that order.

These show the maintainer's real Home Assistant instance (real room and device/person names, e.g. "Lars", "Licht Gabi") -- confirmed acceptable to publish as-is rather than staging anonymized/demo data.

## Visual assets -> Cover image
Not prepared (optional field, 1080x540px). Could be generated in the same visual style as the app icon (navy-to-HA-blue gradient) if wanted later.

## Contact details -> Email
Not filled in here -- this goes to Jolla directly tied to the submitter's account, fill in manually.

## Contact details -> Open source project URL
`https://github.com/silly82/sailhacontrol`

## Publish settings -> Message to QA
Nothing unusual to flag -- the app needs a reachable local Home Assistant instance with a Long-Lived Access Token to actually show data (see README.md's Setup section); without one it just shows the "not configured yet" hint, which is expected and not a bug.

## Still needed for an actual submission (out of scope here)

Deciding whether this app -- built for one person's private local Home Assistant instance -- makes sense as a public Store listing at all, versus staying a GitHub-releases-only project. That's a judgment call for the maintainer, not something to default into.
