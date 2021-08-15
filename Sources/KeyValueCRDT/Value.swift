import Foundation

/// The kinds of values that can be stored in the database.
public enum Value: Equatable, ExpressibleByStringLiteral {
  case null
  case text(String)
  case json(String)
  case blob(mimeType: String, blob: Data)

  public var text: String? {
    if case .text(let text) = self {
      return text
    } else {
      return nil
    }
  }

  public var json: String? {
    if case .json(let json) = self {
      return json
    } else {
      return nil
    }
  }

  public var blob: Data? {
    if case .blob(_, let blob) = self {
      return blob
    } else {
      return nil
    }
  }

  public init(stringLiteral: String) {
    self = .text(stringLiteral)
  }

  internal var entryType: EntryRecord.EntryType {
    switch self {
    case .null: return .null
    case .text: return .text
    case .json: return .json
    case .blob: return .blob
    }
  }
}
