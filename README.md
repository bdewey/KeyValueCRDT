# KeyValueCRDT

## Motivation

Cloud-based document storage, such as iCloud Documents, are fantastic for users with mobile devices but can present headaches for developers. While it is mostly hidden from users, the heart of systems like iCloud Documents is *replication*. When you edit a document that is stored in iCloud Documents, the operating system downloads a local copy of the document. This is fantastic for low-latency and for offline work. As you make changes, a background process will periodically upload your document back to iCloud. However, as soon as you start using the same document from multiple devices, you open the door to the possibility of *version conflicts.* What should iCloud do with changes to the same document that have come from your iPhone and your iPad?

Handling version conflicts is a tricky thing to get right. The goal of `KeyValueCRDT` is to provide a general-purpose file format that works with cloud document storage, reliably and predictably merging changes from multiple devices.

## `KeyValueCRDT` explained step-by-step

### Opening a database

Opening a key-value database is simple: Create an instance of the `KeyValueDatabase` class and give it a URL to your database file. Under the covers, `KeyValueDatabase` uses sqlite to store the key/value pairs.

Note that you need to provide an `Author` when you open the key/value database. `KeyValueDatabase` uses this value to detect conflicting changes to keys. We'll cover `Author` in more detail later.

```swift
let database = try KeyValueDatabase(fileURL: fileURL, author: Author(id: UUID(), name: "test"))
```

### Writing and reading values from the database: The basics

`KeyValueDatabase` has a simple data model -- as the name suggests, it lets you associate values with keys. Keys are arbitrary strings, and values can be:

1. Strings
2. JSON-encoded structures
3. Arbitrary binary blobs

Here's an example of writing & reading text from the database:

```swift
try database.writeText("Hello, world!", to: "key")
XCTAssertEqual(try database.read(key: "key").text, "Hello, world!")
```

Unlike sqlite, `KeyValueDatabase` remembers the value type associated with the key and does not coerce values from one type to another. For example:

```swift
// Note this is storing valid JSON *as text* to the key
try database.writeText("{\"value\": 42}", to: "key")

// If you ask for the text value associated with this key, you'll get it back.
XCTAssertEqual(try database.read(key: "key").text, "{\"value\": 42}")

// However, if you ask for the JSON value associated with the key, you get nil. You wrote a text value, not a JSON value!
XCTAssertNil(try database.read(key: "key").json)
```

### Merging

As described in [Motivation](#motivation), `KeyValueDatabase` is designed for cloud-based documents and the replication that happens under the covers. `merge(source:)` is the key API to support these scenarios. `merge(source:)` will merge keys and values from the source database into the receiver.

The results are intuitive if there are no conflicting changes:

```swift
// Create two databases
let aliceDatabase = try KeyValueDatabase(fileURL: aliceURL, author: Author(id: UUID(), name: "Alice"))
let bobDatabase = try KeyValueDatabase(fileURL: bobURL, author: Author(id: UUID(), name: "Bob"))

// Write some unique values into each database.
try aliceDatabase.writeText("From Alice", to: "alice")
try bobDatabase.writeText("From Bob", to: "bob")

// The "Alice" database can only see what Alice has written -- Bob's changes are in another database
XCTAssertEqual(try aliceDatabase.read(key: "alice").text, "From Alice")
XCTAssertNil(try aliceDatabase.read(key: "bob").text)

// We can merge Bob's changes into Alice's database.
try aliceDatabase.merge(source: bobDatabase)

// Now Alice's database has both Alice and Bob's changes.
XCTAssertEqual(try aliceDatabase.read(key: "alice").text, "From Alice")
XCTAssertEqual(try aliceDatabase.read(key: "bob").text, "From Bob")

// Merge is a one-way operation! Bob's database still doesn't have Alice's changes.
// (Until you merge Alice's database into Bob's, of course!)
XCTAssertEqual(try bobDatabase.read(key: "bob").text, "From Bob")
XCTAssertNil(try bobDatabase.read(key: "alice").text)
```

Things get interesting when there are conflicting changes to the same key. `KeyValueDatabase` implements *multi-value read* semantics to handle conflicts. While you can only *write* a single value for a key, when you *read* from the database, the database may return multiple values: One value for each `Author` that independently wrote to that key.

```swift
// Create two databases
let aliceDatabase = try KeyValueDatabase(fileURL: aliceURL, author: Author(id: UUID(), name: "Alice"))
let bobDatabase = try KeyValueDatabase(fileURL: bobURL, author: Author(id: UUID(), name: "Bob"))

// Write **different values to the same key**
try aliceDatabase.writeText("From Alice", to: "shared")
try bobDatabase.writeText("From Bob", to: "shared")

// Before merging, results are intuitive. Each database sees their own value for the key.
XCTAssertEqual(try aliceDatabase.read(key: "shared").text, "From Alice")
XCTAssertEqual(try bobDatabase.read(key: "shared").text, "From Bob")

try aliceDatabase.merge(source: bobDatabase)

// Question: What value will you get when you read from the "shared" key after merging?
//
// Answer: **both values**
//
// The return value from `read(key:)` is actually an array of `Version` structures.
XCTAssertEqual(try aliceDatabase.read(key: "shared").count, 2)

// The `.text` property will throw an error here because there are multiple versions and it doesn't know
// which one to return.
XCTAssertThrowsError(try aliceDatabase.read(key: "shared").text)
```

Some of the function signatures for `KeyValueDatabase` make more sense now that you know how it handles database merges. Most notably, `KeyValueDatabase.read(key:)` doesn't return a single value; it instead returns an array of `Version` structures:

```swift
public func read(key: String, scope: String = "") throws -> [Version]
```

(We'll talk about `scope` later...)

A `Version` represents a *value written by a single author at a point in time.*

```swift
/// A read-only snapshot of a ``Value`` at a specific point in time.
public struct Version: Equatable {
  /// The ID of the author of this version.
  public let authorID: UUID

  /// When this version was created.
  public let timestamp: Date

  /// The value associated with this version.
  public let value: Value
}
```

To make it easy to read single values from the database, the module `KeyValueCRDT` defines convenience properties on version arrays.

```swift
extension Array where Element == Version {
  // All of these properties:
  //
  // 1) Return `nil` if the value isn't defined or is the wrong type
  // 2) Throw `KeyValueCRDTError.versionConflict` if there are multiple values
  public var text: String? { get throws }
  public var json: String? { get throws }
  public var blob: String? { get throws }
}
```

### Resolving version conflicts

As you see, `KeyValueDatabase` does not try to pick a "winning" version for values associated with keys in the case of merge conflicts. Instead, it relies upon the application layer above the database to know what to do if there are multiple versions. The logic to pick the "winning" version requires application-specific knowledge about what's in the database. Sometimes it might be appropriate to pick the latest value ("last writer wins"), sometimes it may be possible to merge different versions, sometimes you need the user to decide, etc.

You streamline the process of showing a single value in the event of conflicts, the `KeyValueCRDT` module defines the `Resolver` protocol. The job of a `Resolver` is to look at an array of `Version`s for a key and pick the "winning" value. `KeyValueCRDT` also provides `LastWriterWinsResolver`, which picks the winning version based upon timestamp.

```swift
/// A `Resolver` is responsible for picking a single value from an array of possible values.
public protocol Resolver {
  /// Given an array of versions, returns the "winning" value according to some algorithm.
  func resolveVersions(_ versions: [Version]) -> Value?
}

// This extension allows syntax like: `database.read(key: "test").resolved(with: .lastWriterWins)?.text`
extension Array where Element == Version {
  /// Picks a single value from the version array using `resolver`.
  public func resolved(with resolver: Resolver) -> Value? {
    resolver.resolveVersions(self)
  }
}
```

### Advanced Topics

#### Scopes

It can be useful to group related keys together. `KeyValueDatabase` lets you do this with an optional `scope` parameter when reading or writing to the database.

```swift
let database = try KeyValueDatabase(fileURL: nil, author: .alice)

// "Scopes" let you group related keys. For example, this groups the "text" and "coverImage" of a single item
// using a scope.
try database.writeText("scope 1 text", to: "text", scope: "item 1")
try database.writeBlob(Data(), to: "coverImage", scope: "item 1")

// You can use the *same key* in *different scopes* to store *different values*
try database.writeText("scope 2 text", to: "text", scope: "item 2")

// This works because even though the key is the same ("text"), it is used in two different scopes.
XCTAssertEqual("scope 1 text", try database.read(key: "text", scope: "item 1").text)
XCTAssertEqual("scope 2 text", try database.read(key: "text", scope: "item 2").text)
```

If you are used to dealing with file systems, it's tempting to think of *scopes* as *directories*, but this isn't exactly the right mental model. Instead, think of a *scope* as a *key prefix*, where the scope & key are concatenated together to form the "real" key used for storing the value. 

(The problem with the "directory" mental model is it invites you to think of a *scope* as a thing that gets created and deleted separately from *keys*. For example, you need to create a directory before putting files in it. This model has all sorts of edge cases in replication that we don't want to deal with. For example, what happens if one replica deletes a "directory" while another replica adds a new item in that directory? The "scopes and keys are concatenated to make new keys" model avoids these problems.)

#### Listing scopes and keys in the database

