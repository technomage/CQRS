//
//  ObjectEvents.swift
//  Ladi
//
//  Created by Michael Latta on 9/26/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

protocol ObjectEvent : Event {
  func apply<ET>(to obj : ET) -> ET
}

struct SetEvent<E,T : Codable> : Event, Equatable, ObjectEvent, Codable {

  static func == (lhs: SetEvent<E,T>, rhs: SetEvent<E,T>) -> Bool {
    return lhs.seq == rhs.seq && lhs.id == rhs.id && lhs.subject == rhs.subject
  }

  var seq : Int? = nil
  var id : UUID = UUID()
  var project : UUID
  var subject : UUID
  var status : EventStatus = .new
  var path : WritableKeyPath<E, T>
  var undoType : UndoMode = .change
  var value : T
  var prior : T
  
  init(project: UUID, subject: UUID, path: WritableKeyPath<E, T>, value: T, prior: T) {
    self.project = project
    self.subject = subject
    self.path = path
    self.value = value
    self.prior = prior
  }
  
  func reverse() -> Event {
    var e : SetEvent<E, T> = self
    e.id = UUID()
    let v = value
    e.value = prior
    e.prior = v
    return e
  }
  
  func apply<ET>(to obj : ET) -> ET {
    if let o = obj as? E {
      if let result = self.applyPath(to: o, path: self.path) as? ET {
        return result
      } else {
        return obj
      }
    } else {
      return obj
    }
  }
  
  func applyPath(to obj : E, path: WritableKeyPath<E,T>) -> E {
    var o : E = obj
    o[keyPath: path] = value
    return o
  }
  
  func encode() throws -> Data {
    let encoder = JSONEncoder()
    return try encoder.encode(self)
  }
  
  static func decode(from data: Data) throws -> Event {
    return try JSONDecoder().decode(self, from: data)
  }
  
  enum SetEventKey : String, CodingKey {
    case id
    case seq
    case project
    case subject
    case status
    case path
    case undoType
    case value
    case prior
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: SetEventKey.self)
    try container.encode(self.id, forKey: .id)
    try container.encode(self.seq, forKey: .seq)
    try container.encode(self.project, forKey: .project)
    try container.encode(self.subject, forKey: .subject)
    try container.encode(self.status, forKey: .status)
    try container.encode(self.undoType, forKey: .undoType)
    try container.encode(self.value, forKey: .value)
    try container.encode(self.prior, forKey: .prior)
    try container.encode(KeyPathTracker.key(for: self.path), forKey: .path)
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: SetEventKey.self)
    id = try container.decode(UUID.self, forKey: .id)
    seq = try container.decode(Int?.self, forKey: .seq)
    project = try container.decode(UUID.self, forKey: .project)
    subject = try container.decode(UUID.self, forKey: .subject)
    status = try container.decode(EventStatus.self, forKey: .status)
    undoType = try container.decode(UndoMode.self, forKey: .undoType)
    value = try container.decode(T.self, forKey: .value)
    prior = try container.decode(T.self, forKey: .prior)
    path = KeyPathTracker.path(forKey: try container.decode(String.self, forKey: .path)) as! WritableKeyPath<E,T>
  }
}
