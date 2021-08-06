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
