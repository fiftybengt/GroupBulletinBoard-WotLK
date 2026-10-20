# Changelog for "GroupBulletinBoard"

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-10-20

WotLK 3.3.5a (build 12340). Performance update by fiftybengt and Claude.

### Changed
- the request list no longer rebuilds every row every second: each row caches
its text, colour, position and size and only updates what actually changed
- rows far outside the visible part of the list are no longer drawn (when
"don't truncate" is off); scrolling redraws on the next frame
- rows that stay visible are no longer hidden and shown again on every refresh
- faster chat message parsing: word de-duplication uses a lookup table instead
of comparing every word against every other word
- Chinese (zhTW) tag matching lowercases a message once instead of once per tag
- old requests keep expiring while the main window is closed

### Fixed
- removing a player's old request left a hole in the request list, which could
make new requests overwrite existing ones while the window was closed
- clicking, right-clicking or hovering a row always uses the request shown on
that row, even if the list was re-sorted in between

## [1.2.3] - 2026-04-27

### Added
- added support for a functioning Ignore feature via a permanent Ignore List
- added slash commands for the Ignore List. Use `/gbb ignore del` to unignore

### Changed
- improved the sort stability of the request list, so lines should not jump 
around under certain sortings, except when new requests occur
- improved tags for Ulduar requests

### Fixed
- help text in the About section of the GUI should appear more clearly

## [1.2.2] - 2026-02-10

### Changed
- improved tags for WotLK content: Obsidian Sanctum

## [1.2.1] - 2025-12-22

### Fixed
- corrects a select/unselect error in the options for WotLK Filter panel

## [1.2.0] - 2025-11-07

### Added
- added support for Wrath of the Lich King expansion (WotLK) content
- added a larger range of default Blacklist terms

## [1.1.1] - 2024-12-25

### Fixed
- correct some Interface options alignment and text formatting issues

## [1.1.0] - 2024-12-08

### Changed
- added the contents of a request message on mouseover to a tooltip at the top
of the main window. This allows seeing the full message without resizing the
main window

## [1.0.1] - 2024-11-30

### Fixed
- stop minimap button resetting position when Settings updated

## [1.0.0] - 2024-11-27

Initial public release.

### Added
- ported to the WotLK 3.3.5a client.
- README.md

### Fixed
- configuration error causing a UI error from assumed global channel called 
"world". Some servers use "global" channel instead. Assumed global channel 
removed.

### Changed
- removed all version broadcast code.
- removed all third party libraries (AceComm-3.0, CallbackHandler-1.0 and 
LibStub). These were only being used to support the version broadcast code.