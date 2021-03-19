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

@available(iOS 14.0, macOS 11.0, *)
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
  
  @discardableResult func _append(_ event : Event) -> Event {
    var evt = event
    let s = next(evt)
    evt.seq = s
    self.event = evt
    return evt;
  }
}

@available(iOS 14.0, macOS 11.0, *)
open class UndoableEventStore : EventStore {
  public var undo : UndoManager?
  public var undoBatch : [Event]? = nil // Events batched together because undo manager seems to have a limit of 100 per group
  public var batchStack = Stack<String>()
  
  static public var debugUndo = false
  static public var seenRedo : Bool = false // in conjunction with debugUndo
  
  public func startUndoBatch(_ id:String) {
    undoBatch = []
  batchStack.push(id)
  }
  
  public func endUndoBatch(_ batchId: String) {
    if undoBatch != nil && (undoBatch?.count ?? 0) > 0,
       let id = batchStack.pop(), batchId == id {
      guard batchStack.count == 0 else {return}
      print("\n\n@@@@ End undo batch with \(undoBatch!.count) events")
      let batch = undoBatch!
      undoBatch = nil
      undo?.beginUndoGrouping()
      undo?.registerUndo(withTarget: self) { me in
//        print("\n\n@@@@ Undo a batch of \(batch.count) events\n\n")
        self.startUndoBatch("Undo of batch")
        self.undo?.beginUndoGrouping()
        // Reverse all events in the batch
        for e in batch {
//          if UndoableEventStore.debugUndo && String(describing: e).contains("\"Description\"") && String(describing: e).contains("ListChange") {
            print("\n@@@@ \(e.undoType.rawValue) \(String(describing:e))\n\n")
//          }
          let re = self.reverseEvent(e)
          print("\n@@@@ reversed to \(e.undoType.rawValue) \(String(describing:re))\n\n")
          self._append(re)
        }
        self.undo?.endUndoGrouping()
        self.endUndoBatch("Undo of batch")
        print("\n\n@@@@ End of batch undo\n\n")
      }
      undo?.endUndoGrouping()
      undoBatch = nil
    } else {
      print("#### un-nested undo batches")
      ErrTracker.log(Err(msg: "Coding Error",
                         details: "Undo Batches not properly nested \(batchStack)"))
    }
  }

  public override func append(_ event : Event) {
    var e = event
    e.undoType = .change
    self._append(e)
  }
  
  @discardableResult override func _append(_ event : Event) -> Event {
    let e = super._append(event)
    if UndoableEventStore.debugUndo {
//      if event.undoType == .redo {
//        UndoableEventStore.seenRedo = true
//      }
//      print("\n\n@@@@ Applied event \(String(describing: event))\n@@@@     as \(String(describing: e))\n")
    }
    if undoBatch == nil {
      undo?.registerUndo(withTarget: self) { me in
        me.reverse(e)
      }
    } else {
      undoBatch!.append(e)
    }
    if e.seq == nil {
      print("\n\n###### Nil seq!!!! #### \(String(describing: event)) ####\n\n")
      ErrTracker.log(Err(msg: "Coding Error",
                         details: "Event without seq encountered during undo"))
    }
    return e
  }
  
  func reverseEvent(_ event : Event) -> Event {
    let e = event
    var e2 = e.reverse()
    switch e.undoType {
      case .change:
        e2.undoType = .undo
      case .undo:
        e2.undoType = .redo
      case .redo:
        e2.undoType = .undo
    }
    return e2
  }
  
  public func reverse(_ event : Event) {
//    if UndoableEventStore.debugUndo {
//      print("\n\n@@@@ Undo of \(String(describing: event))\n")
//    }
    let e2 = reverseEvent(event)
    let e3 = self._append(e2)
//    if UndoableEventStore.debugUndo {
//      print("\n\n@@@@ Reversed event \(String(describing: event))\n@@@@    to \(String(describing: e3))")
//    }
    if e3.seq == nil {
      print("\n\n###### Nil seq!!!! #### \(String(describing: e2)) ####\n\n")
      ErrTracker.log(Err(msg: "Coding Error",
                         details: "Event without seq encountered during undo"))
    }
  }
}

@available(iOS 14.0, macOS 11.0, *)
public typealias Events = [Event]

@available(iOS 14.0, macOS 11.0, *)
public protocol Event : Codable,Patchable {
  var seq : Seq? { get set }
  var id : UUID { get set }
  var project : UUID { get set }
  var subject : UUID { get set }
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
