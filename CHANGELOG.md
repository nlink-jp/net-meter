# Changelog

All notable changes to net-meter are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
Semantic Versioning.

## [0.1.0] - Unreleased

### Added

- Project scaffold: a menu bar item with a placeholder symbol, and a menu that
  shows the version and quits.
- A single-instance guard, so a second copy exits instead of stacking a second
  menu bar item.
- `make test` checks the documents as well as the code: relative links resolve,
  every English document has its Japanese mirror, and each pair names the same
  flags, make targets and snake_case identifiers.
- Every SF Symbol name the app uses is listed in one place and resolved by a
  test, so a name that does not exist fails the build instead of leaving an
  invisible menu bar item.
