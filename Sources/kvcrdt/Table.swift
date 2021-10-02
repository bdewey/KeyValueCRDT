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
