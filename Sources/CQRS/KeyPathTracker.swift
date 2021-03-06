//
//  KeyPathTracker.swift
//  Ladi
//
//  Created by Michael Latta on 12/4/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation

@available(iOS 14.0, *)
public struct KeyPathTracker {
  static var keyPathToKey = [AnyKeyPath : String]()
  static var keyToKeyPath = [String : AnyKeyPath]()
  
  public static func registerKeyPath(path: AnyKeyPath, key: String) {
    KeyPathTracker.keyPathToKey[path] = key
    KeyPathTracker.keyToKeyPath[key] = path
  }
  static func path(forKey key: String) -> AnyKeyPath {
    return KeyPathTracker.keyToKeyPath[key]!
  }
  static func key(for path: AnyKeyPath) -> String {
    if let name = KeyPathTracker.keyPathToKey[path] {
      return name
    } else {
      ErrTracker.log(Err(msg: "Coding Error", details: "Failed to register key path: \(path)"))
      return ""
    }
  }
}
