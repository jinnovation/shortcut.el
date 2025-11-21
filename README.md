# shortcut.el

Emacs-native package for [Shortcut](https://www.shortcut.com), the project management platform.

> [!WARNING]
> This package is unofficial and not affiliated with Shortcut in any way.

## Features

- **Rich story & epic views**: Browse stories and epics with comprehensive details including
  descriptions, tasks, comments, relationships, health status, and metadata—all in native Emacs
  buffers using magit-section
- **Interactive task management**: Toggle task completion directly in story views with real-time API
  updates and visual feedback
- **Workflow state updates**: Change story states interactively with completion-based selection of
  available workflow states
- **Smart completion & search**: Find stories and epics via `completing-read` with dynamic API
  search, intelligent caching, and visual indicators for completed items
- **List views & filtering**: Browse all stories requested by or assigned to you in sortable,
  interactive vtable-based list views

## Acknowledgments

This package draws **heavy** inspiration from [Jonas Bernoulli (@tarsius)](https://github.com/tarsius)'s considerable
contributions to the Emacs ecosystem -- particularly:

- [Magit](https://magit.vc/);
- [Transient](https://www.gnu.org/software/emacs/manual/html_mono/transient.html);
- [Forge](https://docs.magit.vc/forge/);
- [Magit-Section](https://docs.magit.vc/magit-section/).

If you have found this package helpful in any way, I encourage you to [**sponsor his
work**](https://github.com/sponsors/tarsius).
