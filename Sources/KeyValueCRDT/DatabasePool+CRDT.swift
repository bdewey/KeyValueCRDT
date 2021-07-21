import Foundation
import GRDB

internal extension DatabasePool {
  /// Returns an initialized database pool at the shared location databaseURL
  static func openSharedDatabase(at databaseURL: URL, migrator: DatabaseMigrator) throws -> DatabasePool {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinatorError: NSError?
    var dbPool: DatabasePool?
    var dbError: Error?
    coordinator.coordinate(writingItemAt: databaseURL, options: .forMerging, error: &coordinatorError, byAccessor: { url in
      do {
        dbPool = try openDatabase(at: url, migrator: migrator)
      } catch {
        dbError = error
      }
    })
    if let error = dbError ?? coordinatorError {
      throw error
    }
    return dbPool!
  }

  private static func openDatabase(at databaseURL: URL, migrator: DatabaseMigrator) throws -> DatabasePool {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      // Activate the persistent WAL mode so that
      // readonly processes can access the database.
      //
      // See https://www.sqlite.org/walformat.html#operations_that_require_locks_and_which_locks_those_operations_use
      // and https://www.sqlite.org/c3ref/c_fcntl_begin_atomic_write.html#sqlitefcntlpersistwal
      if db.configuration.readonly == false {
        var flag: CInt = 1
        let code = withUnsafeMutablePointer(to: &flag) { flagP in
          sqlite3_file_control(db.sqliteConnection, nil, SQLITE_FCNTL_PERSIST_WAL, flagP)
        }
        guard code == SQLITE_OK else {
          throw DatabaseError(resultCode: ResultCode(rawValue: code))
        }
      }
    }
    let dbPool = try DatabasePool(path: databaseURL.path, configuration: configuration)

    // Perform here other database setups, such as defining
    // the database schema with a DatabaseMigrator, and
    // checking if the application can open the file:
    try migrator.migrate(dbPool)
    if try dbPool.read(migrator.hasBeenSuperseded) {
      // Database is too recent
      throw KeyValueCRDTError.databaseSchemaTooNew
    }

    return dbPool
  }
}