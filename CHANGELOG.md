# Changelog

All notable changes to Skreenrek are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A Clear button next to the window's title forgets the picked window. Pick Another Window… is still there.
- The picked window gets an outline on screen while the menu is open, and for a moment right after you pick it. The outline never appears in a recording.

### Changed

- With no window picked, the menu is much shorter: no empty preview and no disabled Record button, just Pick Window…. A window that closed uses the same layout.
- The preview has an accent outline while a window is picked, and a red one while recording.
- Settings is now a standard window with General, Agents, and Permissions tabs.
- Everything in the menu lines up on one left and one right edge, and the button labels are centered.
- The menu-bar panel now has a solid background instead of see-through glass.
- The window picker's labels and the recording indicator are solid too, matching the menu.
- The size shown while you drag a region has more room around its text, and its digits no longer shift as the numbers change.
- Skreenrek's app ID is now com.raphaelterrier.skreenrek. macOS will ask once more for Screen Recording and Accessibility; your settings carry over.

### Fixed

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
