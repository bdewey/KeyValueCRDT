import Foundation

struct Table<T>: CustomStringConvertible {
  struct Column {
    let name: String
    let formatter: (T) -> String
  }

  let columns: [Column]
  let rows: [T]

  var description: String {
    var columnWidths = Array(repeating: 0, count: columns.count)
    var rowValues: [[String]] = []
    for row in rows {
      let cells = columns.map { $0.formatter(row) }
      for (index, value) in cells.enumerated() {
        columnWidths[index] = max(columnWidths[index], value.count)
      }
      rowValues.append(cells)
    }
    var result = ""
    for (index, column) in columns.enumerated() {
      result += "\(column.name, columnWidth: columnWidths[index])  "
    }
    result += "\n"
    for (index, _) in columns.enumerated() {
      let underline = String(repeating: "-", count: columnWidths[index])
      result += "\(underline)  "
    }
    result += "\n"
    for row in rowValues {
      for (index, _) in columns.enumerated() {
        result += "\(row[index], columnWidth: columnWidths[index])  "
      }
      result += "\n"
    }
    return result
  }
}

extension String.StringInterpolation {
  mutating func appendInterpolation(_ string: String, columnWidth: Int) {
    let delta = columnWidth - string.count
    appendLiteral(string)
    if delta > 0 {
      let padding = String(repeating: " ", count: delta)
      appendLiteral(padding)
    }
  }
}
