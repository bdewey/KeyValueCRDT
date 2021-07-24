import ArgumentParser
import Foundation
import KeyValueCRDT

enum KVCRDTError: String, Error {
  case invalidFile = "Invalid input file"
}

struct Options: ParsableArguments {
  @Argument(help: "The key-value CRDT file", completion: .file()) var inputFileName: String
}

struct KVCRDT: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "kvcrdt",
    abstract: "View and manipulate a key-value CRDT",
    subcommands: [Statistics.self, List.self],
    defaultSubcommand: Statistics.self
  )
}

struct Statistics: ParsableCommand {
  static var configuration = CommandConfiguration(commandName: "stats", abstract: "Display statistics about the key-value CRDT")

  @OptionGroup var options: Options

  func run() throws {
    guard let fileURL = URL(string: options.inputFileName) else {
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

  @OptionGroup var input: Options

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

KVCRDT.main()
