# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Ability to browse epics and stories with support for cache-based completion
- Ability to update the status of stories from the story view buffer
- Ability to pre-populate the story and epic cache via the Shortcut Search API
- Completed stories in completion candidates are now displayed with strikethrough and grey color
- Story view now displays followers and requester
- Story view now displays epic name alongside epic ID (e.g., "sc-12345 Epic Name")
- Epic field in story view is now interactive - click with mouse or press RET to navigate to the epic's overview
- Description, Tasks, and Comments sections in story view are now always shown, with "empty" placeholder when no content exists
- Story and epic completion candidates are now sorted by completion status within groups (incomplete first, then completed, with most recent IDs first within each status)

### Changed

- Minimum Emacs version requirement bumped from 27.1 to 28.1
- Minimum magit-section version requirement bumped from 3.3.0 to 4.0.0
