//  Licensed to the Apache Software Foundation (ASF) under one
//  or more contributor license agreements.  See the NOTICE file
//  distributed with this work for additional information
//  regarding copyright ownership.  The ASF licenses this file
//  to you under the Apache License, Version 2.0 (the
//  "License"); you may not use this file except in compliance
//  with the License.  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied.  See the License for the
//  specific language governing permissions and limitations
//  under the License.

import Foundation
import GRDB

internal extension DatabasePool {
  /// Returns an initialized database pool at the shared location databaseURL
  static func openSharedDatabase(at databaseURL: URL) throws -> DatabasePool {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinatorError: NSError?
    var dbPool: DatabasePool?
    var dbError: Error?
    coordinator.coordinate(writingItemAt: databaseURL, options: .forMerging, error: &coordinatorError, byAccessor: { url in
      do {
        dbPool = try openDatabase(at: url)
      } catch {
        dbError = error
      }
    })
    if let error = dbError ?? coordinatorError {
      throw error
    }
    return dbPool!
  }

  private static func openDatabase(at databaseURL: URL) throws -> DatabasePool {
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
    return dbPool
  }
}
