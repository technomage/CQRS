//
//  File.swift
//  
//
//  Created by Michael Latta on 4/10/21.
//

import Foundation

private var count : Int = 0
private let enabled = false

public func perfStart(_ msg: String) {
  guard enabled else {return}
  print(String(repeating: "|",count: count)+"+"+" \(Date().timeIntervalSince1970) "+msg)
  count += 1
}

public func perfEnd(_ msg: String) {
  guard enabled else {return}
  count -= 1
  print(String(repeating: "|",count: count)+"-"+" \(Date().timeIntervalSince1970) "+msg)
}

public func perfMsg(_ msg: String, before : Int = 0, after : Int = 0) {
  guard enabled else {return}
  for _ in 0..<before { print("") }
  print(String(repeating: "|",count: count)+" "+" \(Date().timeIntervalSince1970) "+msg)
  for _ in 0..<after { print("") }
}
