- Shortcut REST API docs: https://developer.shortcut.com/api/rest/v3
- Usage examples for the REST API in other languages can be found here:
  https://github.com/useshortcut/api-cookbook
- When adding new user-facing functionality, add a new corresponding record to CHANGELOG.md
- When verifying your solutions, confirm that all member dereferences and field names etc. are in
  line with the API specification. Make any modifications before declaring the solution done.
- Use only Emacs standard libraries, packages, and APIs.
- All IDs for stories, epics, etc. should be prefixed with `sc-` when presented to user.
- All function and variable names should be named `shortcut-<entity>-<action>`. For example, a
  function that gets a story should be called `shortcut-story-get`, not `shortcut-get-story`. In
  line with Emacs convention, use double-hyphens to denote "private" functions and variables,
  e.g. `shortcut--story-get`.

## Reference Implementations

- In general, base your implementations and designs off of the following Emacs packages: Magit and
  Forge. Their implementations can be found on GitHub.

## Testing

- Always run pre-commit hooks
- Run tests: `UNDERCOVER_FORCE=true cask exec buttercup -L . test/`.
- When adding new fixtures, always base them on the Shortcut API schema and verify conformity.
- **Fixture Consistency**: All test fixtures must be internally consistent with each other:
  - If a story references an epic (via `epic_id`), that epic must exist as a fixture
  - If a story or epic references a workflow (via `workflow_id`), that workflow must exist as a fixture
  - All workflow state IDs (via `workflow_state_id`) must correspond to actual states in the workflow fixture
  - All member IDs (in `owner_ids`, `follower_ids`, `requested_by_id`, etc.) must have corresponding member fixtures
  - When creating new fixtures, ensure all referenced entities exist and IDs match exactly
  - This ensures tests accurately reflect real-world API relationships and data integrity
