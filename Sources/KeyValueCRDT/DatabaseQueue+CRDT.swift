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

internal extension DatabaseQueue {
  /// Returns an initialized database pool at the shared location databaseURL
  static func openSharedDatabase(at databaseURL: URL) throws -> DatabaseQueue {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinatorError: NSError?
    var dbQueue: DatabaseQueue?
    var dbError: Error?
    coordinator.coordinate(writingItemAt: databaseURL, options: .forMerging, error: &coordinatorError, byAccessor: { url in
      do {
        dbQueue = try DatabaseQueue(path: url.path)
      } catch {
        dbError = error
      }
    })
    if let error = dbError ?? coordinatorError {
      throw error
    }
    return dbQueue!
  }
}
