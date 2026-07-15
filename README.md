# WowSync UI

> 🖼️ The companion addon that provides the user interface for [WowSync](https://github.com/Eyal-WowHub/WowSync), allowing you to browse characters, manage snapshots, and preview changes before applying them.

WowSync_UI contains the complete visual experience for WowSync. While the core addon handles capturing, storing, and applying snapshots, WowSync_UI provides the window used to interact with those features.

The addon is distributed alongside WowSync and is **loaded on demand**. When you open the WowSync window, the core addon automatically loads the UI—no additional setup is required.

## Requirements

* **WowSync** must be installed and enabled. It is declared as a `RequiredDep`.
* WowSync_UI cannot operate independently; it is loaded and controlled entirely by the core addon.

## Opening the Window

You do not need to load WowSync_UI manually. Open the WowSync window using either of the following methods:

* Click the **WowSync icon in the AddOn Compartment** at the top of the minimap.
* Type `/ws` or `/wowsync`.

The window is the primary interface for managing snapshots, including saving, applying, importing, and exporting them.

The core addon's slash commands are limited to status information and a small set of utility options, such as live tracking, the minimap button, and database reset. Snapshot management requires WowSync_UI.

See the main [WowSync README](https://github.com/Eyal-WowHub/WowSync) for a complete overview of the available features.

## What's Inside

* **Widgets** — reusable interface components such as buttons, scrollable lists, panels, dialogs, splitters, and other shared controls.
* **Panels** — the screens assembled from those widgets, including the character and snapshot lists, import view, apply preview, and the main two-tab window.
* **Core** — shared constants, settings, and snapshot-detail construction utilities.

The window stores its position, dimensions, and panel layout between sessions in the `WowSyncUIDB` saved variables.

## Developer Mode

In an unpackaged WowSync developer build containing the `X-WowSync-DevMode` flag, WowSync_UI exposes a small, development-only import surface for the [WowSync Test Suite](https://github.com/Eyal-WowHub/WowSync_TestSuite).

This allows the test suite to build its explorer using the same shared widgets as the addon. Only an explicitly approved set of widgets is exposed—the addon itself is never made publicly accessible.

This developer interface is not included in packaged releases.

## License

Released under the [MIT License](LICENSE.txt).
