# Changelog

## Unreleased

### Added

- Full-text search to the `kvcdrt` command-line tool

## [0.2.1-beta] - 2021-08-14

### Added

- A diagnostic command-line-option to erase version history. Helpful for recovering when the version history is corrupt.
- Merging now returns a list of changed keys, and there is an option to do a dry-run merge. 
- The `kvcrdt` command-line tool can perform merges.

### Fixed

- Backing up data into another KeyValueDatabase could lead to inconsistencies if the backup was immediately used.
- `UIKeyValueDocument` no longer uses the `backup` API to load data into memory, as this did not trigger observers.

## [0.2.0] - 2021-08-13

### Fixed

- Could not resolve conflicts from more than one *other* authors because the database schema prevented more than one tombstone entry with the same (deleting author, deleting usn) pair.