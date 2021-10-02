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

import ArgumentParser
import Foundation
import KeyValueCRDT

struct InputOptions: ParsableArguments {
  @Argument(help: "The key-value CRDT file", completion: .file()) var inputFileName: String
}

struct KVCRDT: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "kvcrdt",
    abstract: "View and manipulate a key-value CRDT",
    subcommands: [Statistics.self, List.self, Get.self, EraseVersionHistory.self, Merge.self, Search.self],
    defaultSubcommand: Statistics.self
  )
}

struct Statistics: ParsableCommand {
  static var configuration = CommandConfiguration(commandName: "stats", abstract: "Display statistics about the key-value CRDT")

  @OptionGroup var inputOptions: InputOptions

  func run() throws {
    let fileURL = URL(fileURLWithPath: inputOptions.inputFileName)
    let crdt = try KeyValueDatabase(fileURL: fileURL, author: Author(id: UUID(), name: "temp"))
    let stats = try crdt.statistics
    let output = """
    Entries:    \(stats.entryCount)
    Tombstones: \(stats.tombstoneCount)
    Authors:    \(stats.authorCount)
    """
    print(output)
    if !stats.authorTableIsConsistent {
      print("\n\nWARNING: The author table is not consistent with the entries; merges to/from this database will not work.")
      print("Recover by running: kvcrdt erase-version-history <file>")
    }
  }
}

struct List: ParsableCommand {
  static var configuration = CommandConfiguration(abstract: "List the keys in the key-value CRDT")

  @OptionGroup var input: InputOptions
  @Option var scope: String?
  @Option var key: String?

  func run() throws {
    let fileURL = URL(fileURLWithPath: input.inputFileName)
    let crdt = try KeyValueDatabase(fileURL: fileURL, author: Author(id: UUID(), name: "temp"))
    let scopedKeys = try crdt.keys(scope: scope, key: key)
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
    let fileURL = URL(fileURLWithPath: input.inputFileName)
    let crdt = try KeyValueDatabase(fileURL: fileURL, author: Author(id: UUID(), name: "temp"))
    let versions = try crdt.read(key: key, scope: scope)
    let showHeader = versions.count > 1
    for version in versions {
      try printVersion(version, showHeader: showHeader)
    }
  }
}

struct EraseVersionHistory: ParsableCommand {
  static var configuration = CommandConfiguration(abstract: "Erases version history from the CRDT")

  @OptionGroup var input: InputOptions

  func run() throws {
    let fileURL = URL(fileURLWithPath: input.inputFileName)
    let crdt = try KeyValueDatabase(fileURL: fileURL, author: Author(id: UUID(), name: "KVCRDT Command Line"))
    try crdt.eraseVersionHistory()
    print("Success")
  }
}

struct Merge: ParsableCommand {
  static var configuration = CommandConfiguration(abstract: "Merge two databases")

  @Option(help: "The source of new merge records", completion: .file()) var source: String
  @Option(help: "The destination of the merge", completion: .file()) var dest: String
  @Flag(help: "If true, don't actually merge, just compute what changes") var dryRun: Bool = false

  func run() throws {
    if dryRun { print("** Dry run **") }
    let sourceURL = URL(fileURLWithPath: source)
    let destURL = URL(fileURLWithPath: dest)
    let author = Author(id: UUID(), name: "KVCRDT Command Line")
    let sourceDatabase = try KeyValueDatabase(fileURL: sourceURL, author: author)
    let destinationDatabase = try KeyValueDatabase(fileURL: destURL, author: author)
    let changedEntries = try destinationDatabase.merge(source: sourceDatabase, dryRun: dryRun)
    let table = Table<ScopedKey>(columns: [
      Table.Column(name: "Scope", formatter: { $0.scope }),
      Table.Column(name: "Key", formatter: { $0.key }),
    ], rows: Array(changedEntries))
    print("\(table)")
  }
}

struct Search: ParsableCommand {
  static var configuration = CommandConfiguration(abstract: "Perform a full-text search")

  @OptionGroup var input: InputOptions
  @Option(help: "The text to search for") var searchText: String

  func run() throws {
    let fileURL = URL(fileURLWithPath: input.inputFileName)
    let database = try KeyValueDatabase(fileURL: fileURL, author: Author(id: UUID(), name: "kvcrdt"))
    let results = try database.searchText(for: searchText)
    let table = Table<ScopedKey>(columns: [
      Table.Column(name: "Scope", formatter: { $0.scope }),
      Table.Column(name: "Key", formatter: { $0.key }),
    ], rows: results)
    print("\(table)")
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
  case .blob(let mimeType, let data):
    let sizeString = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    print("Binary data: type = \(mimeType), size = \(sizeString)")
  case .null:
    print("DELETED")
  }
}

KVCRDT.main()
