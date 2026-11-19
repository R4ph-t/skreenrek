# Changelog

All notable changes to Skreenrek are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A Clear button next to the window's title forgets the picked window. Pick Another Window… is still there.
- The picked window gets an outline on screen while the menu is open, and for a moment right after you pick it. The outline never appears in a recording.
- A control bar under the picked window sets its size and starts or stops the recording without opening the menu. It never appears in a recording, and Show Control Bar turns it off.
- During a recording the control bar follows the recording indicator: `--no-hud` or turning off Show recording indicator hides it, and when an agent records a window that isn't picked, the bar shows the timer and Stop until the clip ends.
- The control bar's timer shows hours from the first hour on, like 1:02:03. While a clip saves, the spinner and "Saving clip…" sit together in the middle of the bar.
- Without Accessibility, the control bar warns that it can't resize the window, and Record captures the window at its current size.
- An X button at the end of the control bar clears the picked window.
- While recording, the outline around the window turns red, and a region recording gets a red frame just outside the region. It stays solid, never appears in the clip, and hides with the recording indicator.
- When a clip finishes saving with the control bar up, the bar shows Saved with Show in Finder and Copy File Path for a few seconds, in place of the separate Saved indicator.

### Changed

- Recordings are now named after their folder (for example 2026-11-19_091629_safari.mp4) instead of clip.mp4.
- While the control bar is on, a window you record from the menu or the bar stays picked after the clip is saved.
- The control bar's X button is hidden while recording and saving. The bar keeps its width, so nothing moves.
- With `--no-hud` (CLI) or `hud: false` (MCP), or Show recording indicator off, no Saved confirmation appears after a clip, on the bar or as the separate indicator. Agents get the clip's paths from the CLI output or the MCP stop result.
- The control bar's X button has no background at rest, like the Saved buttons, and only highlights on hover and press.
- With no window picked, the menu is much shorter: no empty preview and no disabled Record button, just Pick Window…. A window that closed uses the same layout.
- The preview has an accent outline while a window is picked, and a red one while recording.
- Settings is now a standard window with General, Agents, and Permissions tabs.
- The menu, the control bar, the recording indicator and Settings now share one neutral surface, so they match side by side in light and dark.
- The setup window uses the same surface as Settings: one tone under a transparent title bar, with matching cards.
- Settings shows the app's Dock icon, its name and version at the top of General, on the same solid surface as the window and its toolbar tabs. The window keeps one size, so switching tabs is instant.
- Everything in the menu lines up on one left and one right edge, and the button labels are centered.
- The menu-bar panel now has a solid background instead of see-through glass.
- The window picker's labels and the recording indicator are solid too, matching the menu.
- The size shown while you drag a region has more room around its text, and its digits no longer shift as the numbers change.
- Skreenrek's app ID is now com.raphaelterrier.skreenrek. macOS will ask once more for Screen Recording and Accessibility; your settings carry over.

### Fixed

- The window outline and the control bar now follow the picked window when it moves or resizes, including after a clip.
- The Show Cursor and Write Click Events switches are back at the right edge of the menu.
- Connect in onboarding no longer seems to do nothing. It replaces a leftover `~/.local/bin/skreenrek` link from an old install, finishes when at least one item connects, and shows each failure in red in a window that grows to fit.
- The Size and Frame Rate menus check only the selected item, and Size presets show their dimensions again.
- Custom… in the Size menu opens a panel that stays on screen when another app becomes active.

## [1.0.5] - 2026-11-18

### Fixed

- Clicking the menu-bar icon opens the menu again (broken in 1.0.4).

## [1.0.4] - 2026-11-18

### Added

- When a newer version is available, Settings shows What's new, with that release's notes.
- The menu-bar menu is now a panel with a preview of the picked window, Size and Frame Rate pickers, and a large Record button.

## [1.0.3] - 2026-11-17

### Added

- Setup walks through Screen Recording, Direct Capture, and Accessibility. Screen Recording offers Quit & Reopen, because macOS applies that permission only the next time Skreenrek starts. Direct Capture asks as soon as its step opens. Accessibility is optional.
- Skreenrek won't start a recording until Screen Recording and Direct Capture are granted.
- When a clip is saved, Skreenrek shows Saved, with Show in Finder and Copy File Path. It appears even when the recording indicator is hidden.
- Settings has an Updates row. It checks GitHub for a newer release, upgrades with Homebrew when Skreenrek was installed that way, and then offers Relaunch.
- `skreenrek doctor` checks that each connected agent's command still exists and can be run.

### Changed

- The big red record circle is a compact Record and Stop pill.
- Connecting an agent saves a command path that still works after an upgrade, and repairs a path that points at an old Homebrew install.
- The record-window skill uses Skreenrek's MCP tools when it can, and the command line otherwise.

### Fixed

- A sandboxed shell, such as Codex, now says the shell is sandboxed instead of claiming that Skreenrek.app is corrupt.

## [1.0.2] - 2026-11-17

### Changed

- The menu and Settings use the new Skreenrek look, including the new mark.

### Fixed

- The Homebrew cask asks for macOS Sequoia in the form current Homebrew expects, so install no longer warns that the requirement is deprecated.

## [1.0.1] - 2026-11-17

### Added

- Skreenrek is signed with a Developer ID and notarized, and installs with a Homebrew cask. Permission grants survive an upgrade.

### Changed

- When a window can't take the size you asked for, the menu shows the size you got. The reason is in the tooltip and for VoiceOver.
- After you allow Screen Recording, setup offers Quit & Reopen so the permission takes effect.
- The menu shows Permissions needed… when Screen Recording or Accessibility is off.
- The recording time sits next to the indicator and stays readable as the clip runs longer.
