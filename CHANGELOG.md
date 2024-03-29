# Changelog

## [1.3.1] - 2023-12-22

### Added

- Changed GRDB dependency to a non-forked 6.7 (the first version that enables FTS5 full-text search by default).

## [1.3.0] - 2023-12-22

### Added

- `Sendable` conformance to public value types

## [1.2.1] - 2021-10-13

### Added

- `Applicationidentifier` properties are now `public`

## [1.2.0] - 2021-10-02

### Added

This version adds the concept of "application data versioning." You are STRONGLY encouraged to add an application identifier and application version to file formats built with KeyValueCRDT. This will prevent old versions of your software from corrupting data written by new versions of your software.

## [1.1.0] - 2021-09-30

### Added

- `valuePublisher()` for observing the results of arbitrary database queries.

## [1.0.0] - 2021-09-18

- Updated GRDB and builds with Xcode 13 RC

## [0.4.0-beta] - 2021-09-06

### Changed

I wasn't picking up all changes when merging two different databases created on the same device because they used the same author ID, so I assumed I could ignore entries that I in fact needed.

This version gets rid of the notion of an Author that has a stable UUID identifying all changes from that author across database instances. Instead, the database creates an instanceID for each open instance of the database, and it annotates each instanceID with a textual description (usually the device name) and a timestamp.

This approach will lead to way more entries in the authors table than before. Basically there will be one entry per "write session" instead of one entry per device. Hopefully that won't balloon the database size too much, nor slow down merging too much.

## [0.3.0-beta] - 2021-09-05

### Changed

- UIKeyValueDocument now has a nilable keyValueCRDT property. It will be set to non-nil after the initial open. This dramatically speeds up the time to open a database, because we know we don't need to merge on-disk and in-memory contents.

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