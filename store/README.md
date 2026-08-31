# Jolla Store listing assets

Prepared for a future Harbour submission -- not yet actually submitted (no Jolla/Harbour account set up for this project). Store metadata (description, screenshots) is edited separately from the app binary on the Harbour "application edit page" and doesn't require a new package upload or re-QA.

## Contents

- `description-en.txt`, `description-de.txt` -- store listing description text, ready to paste in.
- `screenshots/` -- three screenshots taken from the SailfishOS SDK emulator (720x1600, native device resolution), showing the room list, the sensor overview, and the light detail controls. These show the developer's real Home Assistant instance (room and device names) -- confirmed acceptable to use as-is rather than staging anonymized/demo data.

## Not verified / still open

The official Harbour FAQ (harbour.jolla.com/faq) does not document specific screenshot dimensions, formats, or a fixed store category list -- unlike the RPM/API rules, there's no automated validator for these, so:

- **Category**: pick one from whatever dropdown the Harbour submission form actually offers when the account is set up; nothing here should be taken as a confirmed category name.
- **Screenshot count/format**: three PNGs at native device resolution is a reasonable default, but the Harbour web UI may resize/crop or have its own preferred aspect ratio -- check there before finalizing.
- **Icon**: the store listing likely reuses the packaged launcher icon (`icons/172x172/harbour-hacontrol.png`) rather than needing a separate upload, but this isn't explicitly confirmed either.

## Still needed for an actual submission (out of scope here)

- A Jolla account with Harbour access.
- Deciding whether this app -- built for one person's private local Home Assistant instance -- makes sense as a public Store listing at all, versus staying a GitHub-releases-only project. That's a judgment call for the maintainer, not something to default into.
