//
//  ObjectEvents.swift
//  Ladi
//
//  Created by Michael Latta on 9/26/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

@available(iOS 14.0, macOS 11.0, *)
public protocol ObjectEvent : Event, DispatchKeys {
  func apply<ET>(to obj : ET) -> ET
}

@available(iOS 14.0, macOS 11.0, *)
public struct SetEvent<E,T : Codable> : Event, Equatable, ObjectEvent, Codable {
  
  public func patch(map: inout [UUID : UUID]) -> SetEvent<E, T>? {
    var e = self
    if let _ = map[id] {
      return nil
    } else {
      e.id = UUID()
      map[id] = e.id
    }
    if let pid = map[project] {
      e.project = pid
    } else {
      return nil
    }
    if map[subject] == nil {
      print("#### No subject found for \(subject) in \(String(describing: self))")
      ErrTracker.log(Err(msg: "Error in cloning project",
                         details: "Failed to find subject for event in cloned project: \(String(describing: self)) map keys: \(String(describing: Array(map.keys)))"))
      return nil
    }
    e.subject = map[subject]!
    if value is [UUID] {
      if let vs = value as? [UUID] {
        let vals = clone(vs, map: map)
        e.value = vals as! T
      }
    }
    if prior is [UUID] {
      if let vs = prior as? [UUID] {
        let vals = clone(vs, map: map)
        e.prior = vals as! T
      }
    }
    return e
  }
  
  private func clone(_ vs:[UUID], map:[UUID:UUID]) -> [UUID] {
    var vals = [UUID]()
    for v in vs {
      if let mv = map[v] {
        vals.append(mv)
      } else {
        vals.append(v)
      }
    }
    return vals
  }

  public static func == (lhs: SetEvent<E,T>, rhs: SetEvent<E,T>) -> Bool {
    return lhs.seq == rhs.seq && lhs.id == rhs.id && lhs.subject == rhs.subject
  }

  public var seq : Seq? = nil
  public var id : UUID = UUID()
  public var project : UUID
  public var subject : UUID
  public var status : EventStatus = .new
  public var path : WritableKeyPath<E, T>
  public var undoType : UndoMode = .change
  public var value : T
  public var prior : T
  
  public init(project: UUID, subject: UUID, path: WritableKeyPath<E, T>, value: T, prior: T) {
    self.project = project
    self.subject = subject
    self.path = path
    self.value = value
    self.prior = prior
  }
  
  public var dispatchKeys : [String]? {
    return [self.subject.uuidString]
  }
  
  public func reverse() -> Event {
    var e : SetEvent<E, T> = self
    e.id = UUID()
    e.seq = nil
    let v = value
    e.value = prior
    e.prior = v
    return e
  }
  
  public func apply<ET>(to obj : ET) -> ET {
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
  
  public func applyPath(to obj : E, path: WritableKeyPath<E,T>) -> E {
    var o : E = obj
    o[keyPath: path] = value
//    print("@@@@ Apply keypath to \(obj) -> \(o) value: \(value)")
    return o
  }
  
  public func encode() throws -> Data {
    let encoder = JSONEncoder()
    encoder.nonConformingFloatEncodingStrategy = JSONEncoder.NonConformingFloatEncodingStrategy.convertToString(positiveInfinity: "0", negativeInfinity: "0", nan: "0")
    return try encoder.encode(self)
  }
  
  public static func decode(from data: Data) throws -> Event {
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
  
  public func encode(to encoder: Encoder) throws {
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
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: SetEventKey.self)
    id = try container.decode(UUID.self, forKey: .id)
    seq = try container.decode(Seq?.self, forKey: .seq)
    project = try container.decode(UUID.self, forKey: .project)
    subject = try container.decode(UUID.self, forKey: .subject)
    status = try container.decode(EventStatus.self, forKey: .status)
    undoType = try container.decode(UndoMode.self, forKey: .undoType)
    value = try container.decode(T.self, forKey: .value)
    prior = try container.decode(T.self, forKey: .prior)
    path = KeyPathTracker.path(forKey: try container.decode(String.self, forKey: .path)) as! WritableKeyPath<E,T>
  }
}
