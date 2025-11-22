# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Story and epic IDs are now clickable throughout the interface - click with mouse or press RET on any ID (e.g., sc-12345) to navigate to that entity. This includes IDs in story lists (vtable), epic references, and story link relationships
- Epic view Health section now displays "Last Updated" field showing when the health status was last modified
- New command `shortcut-stories-list-owned-by-me` to list all stories owned by (assigned to) the current user, accessible via `l o` in the main dispatch menu
- New vtable-based list view for stories requested by current user (accessible via `l s` in transient menu or `M-x shortcut-stories-list-requested-by-me`)
- Ability to browse epics and stories with support for cache-based completion
- Ability to update the status of stories from the story view buffer
- Ability to pre-populate the story and epic cache via the Shortcut Search API
- Completed stories in completion candidates are now displayed with strikethrough and grey color
- Story view now displays followers and requester
- Story view now displays epic name alongside epic ID (e.g., "sc-12345 Epic Name")
- Epic field in story view is now interactive - click with mouse or press RET to navigate to the epic's overview
- Story view now displays Story Links section showing relationships between stories (blocks, relates to, etc.) with clickable links to navigate to related stories
- Description, Tasks, and Comments sections in story view are now always shown, with "empty" placeholder when no content exists
- Story and epic completion candidates are now sorted by completion status within groups (incomplete first, then completed, with most recent IDs first within each status)

### Changed

- Minimum Emacs version requirement bumped from 28.1 to 29.1 (required for vtable support)
- Minimum magit-section version requirement bumped from 3.3.0 to 4.0.0
