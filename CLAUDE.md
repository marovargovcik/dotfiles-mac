# Project Guidelines

## README.md

- Self-contained: never mention another project or the session that prompted a
  change.
- Add packages and commands plainly. Comment only where a non-obvious choice
  would otherwise be undone (e.g. why a tool comes from coursier instead of
  Homebrew).
- Shortest version: one plain-English line saying what does what, then the
  commands. No "why not X" asides, no caveats about tool internals.
- Cover only what stow can't carry: tools installed outside Homebrew, manual
  steps. Don't repeat what a stow package or the Brewfile already declares
  (package names, config values); point at the file and put the "why" as a
  comment there.
- The stow step is `stow */`, not a list of packages.
