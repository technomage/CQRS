//
//  ListEvents.swift
//  Ladi
//
//  Created by Michael Latta on 9/27/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

protocol ListEvent : Event {
  associatedtype R : Equatable
  var parent : UUID? { get }
  var role : R? { get }
}

struct ListChange<E : Codable,R : Equatable&Codable> : Equatable, ListEvent, Codable {
  static func == (lhs: ListChange<E,R>, rhs: ListChange<E,R>) -> Bool {
    return lhs.seq == rhs.seq && lhs.id == rhs.id && lhs.subject == rhs.subject && lhs.parent == rhs.parent && lhs.status == rhs.status && lhs.undoType == rhs.undoType && lhs.role == rhs.role
  }
  
  enum ListAction : Codable {
    case create(at : Int, obj : E)
    case delete(at : Int, obj : E)
    case move(from : Int, to : Int)
    
    enum ListActionType: String, CodingKey {
      case create
      case createAt
      case createObj
      case delete
      case deleteAt
      case deleteObj
      case move
      case moveFrom
      case moveTo
    }
    
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: ListActionType.self)
      switch(self) {
        case .create(let at, let obj):
          try container.encode(at, forKey: .createAt)
          try container.encode(obj, forKey: .createObj)
        case .delete(let at, let obj):
          try container.encode(at, forKey: .deleteAt)
          try container.encode(obj, forKey: .deleteObj)
        case .move(let from, let to):
          try container.encode(from, forKey: .moveFrom)
          try container.encode(to, forKey: .moveTo)
      }
    }
    
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: ListActionType.self)
      if let at = try container.decodeIfPresent(Int.self, forKey: .createAt) {
        let obj = try container.decode(E.self, forKey: .createObj)
        self = .create(at: at, obj: obj)
      } else if let at = try container.decodeIfPresent(Int.self, forKey: .deleteAt) {
        let obj = try container.decode(E.self, forKey: .deleteObj)
        self = .delete(at: at, obj: obj)
      } else {
        let from = try container.decode(Int.self, forKey: .moveFrom)
        let to = try container.decode(Int.self, forKey: .moveTo)
        self = .move(from: from, to: to)
      }
    }
  }
  
  var seq : Int? = nil
  var id : UUID = UUID()
  var project : UUID
  var subject : UUID
  var status : EventStatus = .new
  var undoType : UndoMode = .change
  var action : ListAction
  var parent : UUID?
  var role : R?
  
  init(project: UUID, subject: UUID, action: ListAction) {
    self.project = project
    self.subject = subject
    self.action = action
  }
  
  init(project: UUID, subject: UUID, action: ListAction, parent: UUID?, role: R?) {
    self.init(project: project, subject: subject, action: action)
    self.role = role
  }
  
  func reverse() -> Event {
    var e = self
    e.id = UUID()
    switch action {
      case .create(let at, let obj):
        e.action = .delete(at: at, obj: obj)
      case .delete(let at, let obj):
        e.action = .create(at: at, obj: obj)
      case .move(let f, let t):
        if t > f {
          e.action = .move(from: t-1, to: f)
        } else {
          e.action = .move(from: t, to: f+1)
        }
    }
    return e
  }
  
  func encode() throws -> Data {
    let encoder = JSONEncoder()
    return try encoder.encode(self)
  }
  
  static func decode(from data: Data) throws -> Event {
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
  
  func encode(to encoder: Encoder) throws {
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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: ListChangeType.self)
    id = try container.decode(UUID.self, forKey: .id)
    seq = try container.decode(Int?.self, forKey: .seq)
    project = try container.decode(UUID.self, forKey: .project)
    subject = try container.decode(UUID.self, forKey: .subject)
    status = try container.decode(EventStatus.self, forKey: .status)
    undoType = try container.decode(UndoMode.self, forKey: .undoType)
    action = try container.decode(ListAction.self, forKey: .action)
    parent = try container.decode(UUID?.self, forKey: .parent)
    role = try container.decode(R?.self, forKey: .role)
  }
}
