# Changelog

## Unreleased

### Added

- A diagnostic command-line-option to erase version history. Helpful for recovering when the version history is corrupt.

### Fixed

- Backing up data into another KeyValueDatabase could lead to inconsistencies if the backup was immediately used.

## [0.2.0] - 2021-08-13

### Fixed

- Could not resolve conflicts from more than one *other* authors because the database schema prevented more than one tombstone entry with the same (deleting author, deleting usn) pair.