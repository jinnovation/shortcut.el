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
- Stories in completion candidates are now grouped by epic
- Stories in completion candidates are now sorted by completion status within their respective epic
  groups

### Changed

- Minimum Emacs version requirement bumped from 27.1 to 28.1
- Minimum magit-section version requirement bumped from 3.3.0 to 4.0.0
