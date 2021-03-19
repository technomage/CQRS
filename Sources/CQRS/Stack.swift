//
//  Stack.swift
//  A simple stack implementation
//
//  Created by Michael Latta on 9/26/20.
//

import Foundation
public struct Stack<Element> : ExpressibleByArrayLiteral where Element: Equatable {
  private var storage = [Element]()
  func peek() -> Element? { storage.last }
  mutating func push(_ element: Element) { storage.append(element)  }
  mutating func pop() -> Element? { storage.popLast() }
  var count : Int { return storage.count }
  public init(arrayLiteral elements: Element...) { storage = elements }
}

extension Stack: Equatable {
  public static func == (lhs: Stack<Element>, rhs: Stack<Element>) -> Bool { lhs.storage == rhs.storage }
}

extension Stack: CustomStringConvertible {
  public var description: String { "\(storage)" }
}
