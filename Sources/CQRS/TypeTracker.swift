//
//  TypeTracker.swift
//  Ladi
//
//  This struct tracks types by name to allow deserializing types from json
//  when the type is polymorphic (event types are encoded in the log file and must
//  be converted to type instances to deserialize the contents of the file)
//
//  Created by Michael Latta on 12/4/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation

struct TypeTracker {
  static var classes = [String : Any.Type]()
  
  static func register(_ cls : Any.Type, key: String) {
    classes[key] = cls
  }
  
  static func typeFromKey(_ key: String) -> Any.Type? {
    return TypeTracker.classes[key]
  }
  
  static func keyFromType(_ cls: Any.Type) -> String? {
    for k in classes.keys {
      if classes[k] == cls {
        return k
      }
    }
    return nil
  }
}
