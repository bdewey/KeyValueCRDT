# Changelog

## [0.2.0] - 2021-08-13

### Fixed

- Could not resolve conflicts from more than one *other* authors because the database schema prevented more than one tombstone entry with the same (deleting author, deleting usn) pair.