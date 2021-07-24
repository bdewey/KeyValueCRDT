import ArgumentParser
import Foundation
import KeyValueCRDT

enum KVCRDTError: String, Error {
  case invalidFile = "Invalid input file"
}

struct InputOptions: ParsableArguments {
  @Argument(help: "The key-value CRDT file", completion: .file()) var inputFileName: String
}

struct KVCRDT: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "kvcrdt",
    abstract: "View and manipulate a key-value CRDT",
    subcommands: [Statistics.self, List.self, Get.self],
    defaultSubcommand: Statistics.self
  )
}

struct Statistics: ParsableCommand {
  static var configuration = CommandConfiguration(commandName: "stats", abstract: "Display statistics about the key-value CRDT")

  @OptionGroup var inputOptions: InputOptions

  func run() throws {
    guard let fileURL = URL(string: inputOptions.inputFileName) else {
      throw KVCRDTError.invalidFile
    }
    let crdt = try KeyValueCRDT(fileURL: fileURL, author: Author(id: UUID(), name: "temp"))
    let stats = try crdt.statistics
    let output = """
Entries:    \(stats.entryCount)
Tombstones: \(stats.tombstoneCount)
Authors:    \(stats.authorCount)
"""
    print(output)
  }
}

struct List: ParsableCommand {
  static var configuration = CommandConfiguration(abstract: "List the keys in the key-value CRDT")

  @OptionGroup var input: InputOptions

  func run() throws {
    guard let fileURL = URL(string: input.inputFileName) else {
      throw KVCRDTError.invalidFile
    }
    let crdt = try KeyValueCRDT(fileURL: fileURL, author: Author(id: UUID(), name: "temp"))
    let scopedKeys = try crdt.keys
    let table = Table<ScopedKey>(columns: [
      Table.Column(name: "Scope", formatter: { $0.scope }),
      Table.Column(name: "Key", formatter: { $0.key }),
    ], rows: scopedKeys)
    print("\(table)")
  }
}

struct Get: ParsableCommand {
  static var configuration = CommandConfiguration(abstract: "Gets a value from the key-value CRDT")

  @Option var scope: String = ""
  @Option var key: String
  @OptionGroup var input: InputOptions

  func run() throws {
    guard let fileURL = URL(string: input.inputFileName) else {
      throw KVCRDTError.invalidFile
    }
    let crdt = try KeyValueCRDT(fileURL: fileURL, author: Author(id: UUID(), name: "temp"))
    let versions = try crdt.read(key: key, scope: scope)
    let showHeader = versions.count > 1
    for version in versions {
      try printVersion(version, showHeader: showHeader)
    }
  }
}

func printVersion(_ version: Version, showHeader: Bool = false) throws {
  if showHeader {
    print("Updated from \(version.authorID) at \(version.timestamp):")
  }
  switch version.value {
  case .text(let text):
    print(text)
  case .json(let json):
    let data = json.data(using: .utf8)!
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    let formattedOutput = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(data: formattedOutput, encoding: .utf8)!)
  case .blob(let data):
    print("Binary data: \(data.count) byte(s)")
  case .null:
    print("DELETED")
  }
}

KVCRDT.main()
