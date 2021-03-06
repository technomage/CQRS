//
//  ListEvents.swift
//  Ladi
//
//  Created by Michael Latta on 9/27/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

@available(iOS 14.0, macOS 11.0, *)
public protocol ListEvent : Event, DispatchKeys {
  associatedtype R : Equatable,Codable
  var parent : UUID? { get }
  var role : R? { get }
}

public protocol WithProject {
  var project:UUID {get set}
}

public protocol ListEventSavable {
  func prepareForSaveAs(project: UUID, fromProject: UUID) -> Event
}

@available(iOS 14.0, macOS 11.0, *)
public struct ListChange<E : WithID&Patchable,R : Equatable&Codable&RoleEnum> : Equatable, ListEvent, Codable, ListEventWithParent, ListEventSavable {

  func patchProject(obj: E, project: UUID, fromProject: UUID) -> E {
    var o = obj
    if o.id == fromProject {
      o.id = project
    }
    if var o2 = o as? WithProject {
      o2.project = project
      return o2 as! E
    } else {
      return o
    }
  }
  public func prepareForSaveAs(project: UUID, fromProject: UUID) -> Event {
    var e = self
    if case let .create(after, obj) = action {
      e.action = .create(after: after, obj: patchProject(obj: obj, project: project, fromProject: fromProject))
    } else if case let .delete(after, obj) = action {
      e.action = .create(after: after, obj: patchProject(obj: obj, project: project, fromProject: fromProject))
    }
    return e
  }
  
  public func preEncode() -> NSData? {
    switch action {
      case .create(after:_, obj: let obj):
        if let o = obj as? WithCustomCoding {
          return o.preEncode()
        } else {
          return nil
        }
      case .delete(after:_, obj: let obj):
        if let o = obj as? WithCustomCoding {
          return o.preEncode()
        } else {
          return nil
        }
      case .move:
        return nil
    }
  }
  
  public func postDecode(_ data: NSData) -> Self {
    switch action {
      case .create(after: let a, obj: let obj):
        if let o = obj as? WithCustomCoding {
          let ob = o.postDecode(data) as! E
          var ret = self
          ret.action = .create(after: a, obj: ob)
          return ret
        } else {
          return self
        }
      case .delete(after: let a, obj: let obj):
        if let o = obj as? WithCustomCoding {
          let ob = o.postDecode(data) as! E
          var ret = self
          ret.action = .delete(after: a, obj: ob)
          return ret
        } else {
          return self
        }
      case .move:
        return self
    }
  }
  
  
  private func safelyPatch(obj: E, map: inout [UUID : UUID]) -> E? {
    var o2 : E? = obj
    if var op = obj as? WithProject {
      op.project = project
      if let obj = (op as! E).patch(map: &map) {
        o2 = obj
      } else {
        o2 = nil
      }
    } else {
      o2 = obj.patch(map: &map)
    }
    return o2
  }
  
  public func patch(map: inout [UUID : UUID]) -> Self? {
    var e = self
    if let _ = map[id] {
      return nil
    } else {
      e.id = UUID()
      map[id] = e.id
    }
    if case let .create(a, o) = e.action {
      if let obj = safelyPatch(obj: o, map: &map) {
        e.project = map[project]!
        e.action = .create(after: a != nil ? map[a!] : nil, obj: obj)
      } else {
        return nil
      }
    } else if case let .delete(a, o) = e.action {
      e.project = map[project]!
      if let obj = safelyPatch(obj: o, map: &map) {
        if let op = obj as? WithProject, op.project != e.project {
          print("#### Danger will robinson !!!!")
        }
//      if var obj = o.patch(map: &map) {
//        if var op = obj as? WithProject {
//          op.project = e.project
//          obj = op as! E
//        }
        e.action = .delete(after: a != nil ? map[a!] : nil, obj: obj)
      } else {
        return nil
      }
    } else if case let .move(from, after, wasAfter) = e.action {
      e.action = .move(from: map[from]!,
                       after: after != nil ? map[after!]! : nil,
                       wasAfter: wasAfter != nil ? map[wasAfter!]! : nil)
    }
    e.project = map[project]!
    e.subject = map[subject]!
    if let p = parent, let par = map[p] {
      e.parent = par
    }
    return e
  }
  
  public static func == (lhs: ListChange<E,R>, rhs: ListChange<E,R>) -> Bool {
    return lhs.seq == rhs.seq && lhs.id == rhs.id && lhs.subject == rhs.subject && lhs.parent == rhs.parent && lhs.status == rhs.status && lhs.undoType == rhs.undoType && lhs.role == rhs.role
  }
  
  public var dispatchKeys : [String]? {
    ["\(self.parent?.uuidString ?? "")::\(self.role?.rawValue ?? "")", self.subject.uuidString]
  }
  
  public enum ListAction : Codable {
    case create(after : UUID?, obj : E)
    case delete(after: UUID?, obj : E)
    case move(from : UUID, after : UUID?, wasAfter: UUID?)
    
    enum ListActionType: String, CodingKey {
      case create
      case createAfter
      case createObj
      case delete
      case deleteAfter
      case deleteObj
      case move
      case moveFrom
      case moveAfter
      case moveWasAfter
    }
    
    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: ListActionType.self)
      switch(self) {
        case .create(let at, let obj):
          try container.encode(at, forKey: .createAfter)
          try container.encode(obj, forKey: .createObj)
        case .delete(let at, let obj):
          try container.encode(at, forKey: .deleteAfter)
          try container.encode(obj, forKey: .deleteObj)
        case .move(let from, let to, let was):
          try container.encode(from, forKey: .moveFrom)
          try container.encode(to, forKey: .moveAfter)
          try container.encode(was, forKey: .moveWasAfter)
      }
    }
    
    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: ListActionType.self)
      if container.contains(.createObj) {
        let obj = try container.decode(E.self, forKey: .createObj)
        let after = try container.decodeIfPresent(UUID?.self, forKey: .createAfter) ?? nil
        self = ListAction.create(after: after, obj: obj)
      } else if container.contains(.deleteObj) {
        let after = try container.decodeIfPresent(UUID?.self, forKey: .deleteAfter) ?? nil
        let obj = try container.decode(E.self, forKey: .deleteObj)
        self = .delete(after: after, obj: obj)
      } else {
        let from = try container.decode(UUID.self, forKey: .moveFrom)
        let after = try container.decode(UUID?.self, forKey: .moveAfter)
        let wasAfter = try container.decode(UUID?.self, forKey: .moveWasAfter)
        self = .move(from: from, after: after, wasAfter: wasAfter)
      }
    }
  }
  
  public var seq : Seq? = nil
  public var id : UUID = UUID()
  public var project : UUID
  public var subject : UUID
  public var status : EventStatus = .new
  public var undoType : UndoMode = .change
  public var action : ListAction
  public var parent : UUID?
  public var role : R?
  
  public init(project: UUID, subject: UUID, action: ListAction) {
    self.project = project
    self.subject = subject
    self.action = action
  }
  
  public init(project: UUID, subject: UUID, action: ListAction, parent: UUID?, role: R?) {
    self.init(project: project, subject: subject, action: action)
    self.role = role
    self.parent = parent
  }
  
  public func reverse() -> Event {
    var e = self
    e.id = UUID()
    e.seq = nil
    switch action {
      case .create(let after, let obj):
        e.action = .delete(after: after, obj: obj)
      case .delete(let after, let obj):
        e.action = .create(after: after, obj: obj)
      case .move(let from, let after, let wasAfter):
        e.action = .move(from: from, after: wasAfter, wasAfter: after)
    }
    return e
  }
  
  public func encode() throws -> Data {
    let encoder = JSONEncoder()
    encoder.nonConformingFloatEncodingStrategy = JSONEncoder.NonConformingFloatEncodingStrategy.convertToString(positiveInfinity: "0", negativeInfinity: "0", nan: "0")
    return try encoder.encode(self)
  }
  
  public static func decode(from data: Data) throws -> Event {
    return try JSONDecoder().decode(self, from: data)
  }

  enum ListChangeType: String, CodingKey {
    case id
    case seq
    case project
    case subject
    case status
    case undoType
    case action
    case parent
    case role
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: ListChangeType.self)
    try container.encode(self.id, forKey: .id)
    try container.encode(self.seq, forKey: .seq)
    try container.encode(self.project, forKey: .project)
    try container.encode(self.subject, forKey: .subject)
    try container.encode(self.status, forKey: .status)
    try container.encode(self.undoType, forKey: .undoType)
    try container.encode(self.action, forKey: .action)
    try container.encode(self.parent, forKey: .parent)
    try container.encode(self.role, forKey: .role)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: ListChangeType.self)
    id = try container.decode(UUID.self, forKey: .id)
    seq = try container.decode(Seq?.self, forKey: .seq)
    project = try container.decode(UUID.self, forKey: .project)
    subject = try container.decode(UUID.self, forKey: .subject)
    status = try container.decode(EventStatus.self, forKey: .status)
    undoType = try container.decode(UndoMode.self, forKey: .undoType)
    action = try container.decode(ListAction.self, forKey: .action)
    parent = try container.decode(UUID?.self, forKey: .parent)
    role = try container.decode(R?.self, forKey: .role)
  }
}
