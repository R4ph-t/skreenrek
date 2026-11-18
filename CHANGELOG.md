# Changelog

All notable changes to Skreenrek are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- When a newer version is available, Settings shows What's new, with that release's notes.

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
