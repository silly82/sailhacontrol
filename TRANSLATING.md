# Translating HA Control

All texts in the app are written in **English** in the source code. Any other
language is a translation file in `translations/`:

| File | Purpose |
|------|---------|
| `harbour-hacontrol.ts` | Template with every text, no translations. Start a new language from here. |
| `harbour-hacontrol-de.ts` | German |
| `harbour-hacontrol-<lang>.ts` | Your language. `<lang>` is the locale code, e.g. `fi`, `fr`, `sv`, `pt_BR`. |

The app picks the file that matches the phone's language automatically. If
there is none, it shows the English texts.

## Adding a new language

1. Copy the template and set the language (Finnish is used as the example here):

   ```sh
   ./translations/new-language.sh fi
   ```

   (This is the same as `cp translations/harbour-hacontrol.ts translations/harbour-hacontrol-fi.ts`
   plus adding `language="fi"` to the `<TS>` tag.)

2. Translate the texts. You can use either of these:
   - **Qt Linguist** (`linguist translations/harbour-hacontrol-fi.ts`). This is
     the easiest option, and it shows the context and checks placeholders.
   - **Any text editor.** Write the translation between `<translation>` and
     `</translation>`, then remove `type="unfinished"`:

     ```xml
     <source>All lights off</source>
     <translation>Kaikki valot pois</translation>
     ```

3. Optional: add a translated app name to `harbour-hacontrol.desktop`, e.g.
   `Name[fi]=HA Control`.

4. Open a pull request, or send the `.ts` file via the forum or an issue.

You do **not** need to change `harbour-hacontrol.pro` or the RPM spec. Every
`translations/harbour-hacontrol-*.ts` file is built and packaged automatically.

## Things to keep in mind

- **Placeholders** such as `%1` must stay in the translation. They are replaced
  with a number or name at runtime, e.g. `Current: %1 °C`.
- **Plural forms**: `%n light(s) on` has one entry per plural form of your
  language (Qt Linguist shows the right number of fields).
- Lines starting with `//:` in the QML are notes for translators. They show up
  as comments in Linguist.
- `SailfishOS Phone` is only the *default* device name sent to Home Assistant.
  It is fine to leave it untranslated.
- Leave product names (Home Assistant, Sailfish Secrets, Long-Lived Access
  Token) untranslated unless your language has an established term.

## For developers: updating the files after changing texts

The build runs `lupdate` and refreshes every `.ts` file. To do it by hand:

```sh
lupdate -noobsolete qml src -ts translations/harbour-hacontrol.ts translations/harbour-hacontrol-*.ts
```

New or changed texts show up as unfinished in every language until a
translator handles them.
