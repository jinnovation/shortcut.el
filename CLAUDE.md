- Shortcut REST API docs: https://developer.shortcut.com/api/rest/v3
- Usage examples for the REST API in other languages can be found here: https://github.com/useshortcut/api-cookbook
- Use only Emacs standard libraries, packages, and APIs.
- All IDs for stories, epics, etc. should be prefixed with `sc-` when presented to user.
- All function and variable names should be named `shortcut-<entity>-<action>`. For example, a
  function that gets a story should be called `shortcut-story-get`, not `shortcut-get-story`. In
  line with Emacs convention, use double-hyphens to denote "private" functions and variables,
  e.g. `shortcut--story-get`.

## Reference Implementations

- In general, base your implementations and designs off of the following Emacs packages: Magit and
  Forge. Their implementations can be found on GitHub.
