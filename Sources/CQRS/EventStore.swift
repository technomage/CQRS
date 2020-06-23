//
//  EventStore.swift
//  Ladi
//
//  Created by Michael Latta on 9/23/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

public protocol Aggregator {
}

@available(iOS 13.0, *)
open class EventStore : ObservableObject {
  var seq = Seq()
  @Published public var event : Event? = nil
  public var log : EventLog
  
  public init() {
    let l = EventLog()
    self.log = l
    self.$event.subscribe(log)
  }
  
  func next(_ evt: Event) -> Seq {
    if evt.seq != nil {
      if evt.seq!.after(self.seq) {
        self.seq = evt.seq!
      }
    } else {
      self.seq = self.seq.next(Seq.localID!)
    }
    return self.seq
  }
  
  public func append(_ event : Event) {
    self._append(event)
  }
  
  func _append(_ event : Event) {
    var evt = event
    let s = next(evt)
    evt.seq = s
    self.event = evt
  }
}

@available(iOS 13.0, *)
open class UndoableEventStore : EventStore {
  public var undo : UndoManager?
  
  public override func append(_ event : Event) {
    var e = event
    e.undoType = .change
    self._append(e)
  }
  
  override func _append(_ event : Event) {
    undo?.registerUndo(withTarget: self) { me in
      me.reverse(event)
    }
    super._append(event)
  }
  
  public func reverse(_ event : Event) {
    var e = event
    switch e.undoType {
      case .change:
        e.undoType = .undo
      case .undo:
        e.undoType = .redo
      case .redo:
        e.undoType = .undo
    }
    let e2 = e.reverse()
    self._append(e2)
  }
}

public typealias Events = [Event]

public protocol Event : Codable {
  var seq : Seq? { get set }
  var id : UUID { get }
  var project : UUID { get }
  var subject : UUID { get }
  var status : EventStatus { get set }
  var undoType: UndoMode { get set }
  //
  func reverse() -> Event
  func encode() throws -> Data
  static func decode(from data: Data) throws -> Event
}

public protocol Named {
  var id : UUID {get}
  var name : String {get}
}

public enum EventStatus : Int, Codable {
  case new       // Event has been created and not yet saved outside RAM
  case queued    // Stored in the event store locally just in RAM
  case cached    // Event has been cached to local storage
  case persisted // Event has been saved to iCloud
}

public enum UndoMode : Int, Codable {
  case change    // A normal change
  case undo      // undo a prior change
  case redo      // reapply a prior change
}
