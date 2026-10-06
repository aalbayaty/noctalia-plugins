# App Cheatsheet

A cheatsheet-style panel that lists the GUI applications installed on the
system, grouped by category. Click an app to launch it. There is no search on
purpose: the Noctalia launcher already does that. This is for seeing what is
installed at a glance.

| Field | Value |
| --- | --- |
| ID | `aalbayaty/app-cheatsheet` |
| Entries | Data service: `data`; bar widget: `apps`; panel: `cheatsheet` |
| Requires | `grep`, `gio` (GLib) on `PATH` |

## Usage

Enable the plugin, then add the `apps` widget from the bar widget picker.
Clicking its glyph toggles the panel. To open it without a bar widget, or from
a compositor keybind:

```sh
noctalia msg panel-toggle aalbayaty/app-cheatsheet:cheatsheet
```

## What is listed

Every `.desktop` file under `$XDG_DATA_HOME/applications` and each
`applications` directory in `$XDG_DATA_DIRS` (Nix profiles and Flatpak exports
included), minus entries that are `NoDisplay`, `Hidden`, `Terminal=true`, not
`Type=Application`, or excluded for the current desktop by
`OnlyShowIn`/`NotShowIn`. When two directories ship the same desktop id, the
earlier one wins, as the spec requires. The list is rescanned each time the
panel opens.

## Categories

Groups come from each entry's `Categories=`. Specific sub-categories are
checked before the broad ones, so a browser (`Network;WebBrowser`) lands in
Browsers rather than Remote & Network:

| Group | Matched from |
| --- | --- |
| Browsers | WebBrowser |
| Communication | Chat, InstantMessaging, Email, Telephony, VideoConference, IRCClient |
| Games | Game |
| Development | Development, IDE, TextEditor |
| Office | Office |
| Graphics | Graphics |
| Media | AudioVideo, Audio, Video, Player, Recorder |
| Remote & Network | RemoteAccess, P2P, FileTransfer, Network |
| System & Settings | System, Settings, FileManager, Monitor, TerminalEmulator |
| Utilities | Utility |
| Other | everything else |

## Settings

- **Columns**: maximum number of columns; narrow outputs use fewer.
- **Category overrides**: one entry per app, `App=Category`. `App` is the name
  shown in the panel or the desktop id (`org.remmina.Remmina`), case-insensitive.
  `Category` is a built-in group or any name of your own; custom groups are
  listed first, alphabetically. Example: `Steam=Games`, `Bitwarden=Security`.
- **Hidden apps**: names or desktop ids to leave out.

## Tests

From the repo root:

```sh
luau app-cheatsheet/tests/service_test.luau
luau app-cheatsheet/tests/panel_test.luau
```
