//
//  ListAggrregator.swift
//  Ladi
//
//  Created by Michael Latta on 10/4/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

public protocol ListEntry : Equatable, Codable {
  var id : UUID { get }
}

public protocol NamedListEntry : ListEntry {
  var name : String { get set }
}

@available(iOS 13.0, *)
open class ListAggregator<E : ListEntry, R : Hashable&Codable> : Subscriber, ObservableObject, Aggregator {
  public typealias Input = ListChange<E,R>
  public typealias Failure = Never
  public typealias LE = ListChange<E,R>
  public typealias ListFilterClosure = (LE) -> Bool
  public typealias ChildAggregatorClosure = (_ store: UndoableEventStore, _ par : ListAggregator<E,R>, _ obj: E) -> ObjectAggregator<E,R>
  
  public var role : R?
  public var filter : ListFilterClosure?

  @Published public var list : [E] = []
  @Published public var events : [LE] = []
  var sub : Subscription?
  public var store : UndoableEventStore?
  public var childConfig : ChildAggregatorClosure?
  public var objAggs = Dictionary<UUID, ObjectAggregator<E,R>>()
  var objCancels = Dictionary<UUID, AnyCancellable>()
  public var parent : UUID?
  public var name : String?
  
  public init() {
    
  }
  
  public convenience init(filter: @escaping ListFilterClosure) {
    self.init()
    self.filter = filter
  }
  
  public convenience init(config : @escaping ChildAggregatorClosure) {
    self.init()
    self.childConfig = config
  }
  
  public convenience init(config : @escaping ChildAggregatorClosure,
                   filter: @escaping ListFilterClosure) {
    self.init()
    self.childConfig = config
    self.filter = filter
  }
  
  public convenience init(role: R) {
    self.init()
    self.role = role
  }
  
  public convenience init(role: R, store: UndoableEventStore) {
    self.init()
    self.role = role
    self.store = store
    self.subscribeToStore()
  }
  
  public convenience init(role: R, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
  }
  
  public convenience init(role: R, store: UndoableEventStore, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
    self.store = store
    self.subscribeToStore()
  }
  
  public convenience init(role: R, store: UndoableEventStore, parent: UUID, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
    self.parent = parent
    self.store = store
    self.subscribeToStore()
  }
  
  public convenience init(role: R, store: UndoableEventStore, parent: UUID, config: @escaping ChildAggregatorClosure, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
    self.childConfig = config
    self.parent = parent
    self.store = store
    self.subscribeToStore()
  }
  
  public convenience init(role: R, config : @escaping ChildAggregatorClosure) {
    self.init()
    self.role = role
    self.childConfig = config
  }
  
  public convenience init(store : UndoableEventStore) {
    self.init()
    self.store = store
    self.subscribeToStore()
  }
  
  public convenience init(store : UndoableEventStore, filter: @escaping ListFilterClosure) {
    self.init(store: store)
    self.filter = filter
  }
  
  public func subscribeToStore() {
    guard self.store != nil else {return}
    self.store!.log
      .filter({e in e is ListChange<E,R>})
      .map{e in e as! ListChange<E,R>}
      .subscribe(self)
  }
  
  public func setName(_ name : String) -> Self {
    self.name = name
    return self
  }
  
  /// Find the object prior to the obj with the given ID
  public func find(before: UUID) -> E? {
    for i in 0..<self.list.count {
      if self.list[i].id == before {
        if i == 0 {
          return nil
        } else {
          return self.list[i-1]
        }
      }
    }
    return nil
  }
  
  /// Find the object after to the obj with the given ID
  public func find(after: UUID) -> E? {
    for i in 0..<self.list.count {
      if self.list[i].id == after {
        if i == self.list.count-1 {
          return nil
        } else {
          return self.list[i+1]
        }
      }
    }
    return nil
  }
  
  /// Locate the object in the list with the given id
  public func find(id: UUID) -> E? {
    for i in 0..<self.list.count {
      if self.list[i].id == id {
        return self.list[i]
      }
    }
    return nil
  }
  
  /// Delete an object from the list for a given project.  This emits events that are processed in the event store.
  public func delete(project: UUID, obj: E) {
    let prior = self.find(before: obj.id)
    let e = ListChange<E,R>(project: project, subject: obj.id,
                            action: .delete(after: prior?.id ?? nil, obj: obj))
    self.store?.append(e)
  }
  
  /// Move an object to a different position in the list following a given obj id
  public func move(project: UUID, from: UUID, after: UUID?, wasAfter: UUID?) {
    let e = ListChange<E,R>(project: project, subject: from,
                            action: .move(from: from, after: after, wasAfter: wasAfter))
    self.store?.append(e)
  }
  
  /// Delete an object from the list with a given partent and role
  public func delete(project: UUID, obj: E, in parent : UUID, role: R) {
    let prior = self.find(before: obj.id)
    let e = ListChange<E,R>(project: project, subject: obj.id,
                            action: .delete(after: prior?.id ?? nil, obj: obj),
                            parent: parent, role: role)
    self.store?.append(e)
  }
  
  /// Move an object within a list given parent and role
  public func move(project: UUID, from: UUID, after: UUID?, wasAfter: UUID?, in parent: UUID, role: R) {
    let e = ListChange<E,R>(project: project, subject: from,
                            action: .move(from: from, after: after, wasAfter: wasAfter),
                            parent: parent, role: role)
    self.store?.append(e)
  }
  
  /// Respond to a new subscription
  public func receive(subscription: Subscription) {
    sub = subscription
    subscription.request(Subscribers.Demand.unlimited)
  }
  
  /// Filter events against the role and filter for the aggregator
  public func filterEvent(_ input: LE) -> Bool {
    guard !self.events.contains(where: { e in e.id == input.id}) else {return false}
//    NSLog("\n\n@@@@ Filter list event \(input) for role: \(role) in \(name)\n\n")
    guard self.role == nil || self.role == input.role else {return false}
    guard self.filter != nil else {return true}
    return self.filter!(input)
  }
  
  /// Receive a new event for the aggregator
  public func receive(_ input: LE) -> Subscribers.Demand {
    if self.filterEvent(input) {
      events.append(input)
      switch input.action {
        case .create(let after, let obj) :
//          NSLog("\n\n@@@@ Inserting object in \(String(describing: name)) \(String(describing: role)) of \(String(describing: parent)) list \(obj) has child config: \(self.childConfig != nil)\n\n")
          let oa = self.childConfig?(store!, self, obj) ??
            ObjectAggregator<E,R>(obj: obj, store: self.store) { e in e.subject == obj.id}
          // NSLog("@@@@ Child aggregator has children: \(oa.childAggregators)")
          oa.store = self.store
          self.store?.log.subscribe(oa)
          self.objAggs[obj.id] = oa
          let afterIndex = list.firstIndex { d in
            d.id == after
            }
          self.list.insert(obj, at: afterIndex != nil ? afterIndex!+1 : 0)
          self.objCancels[obj.id] = oa.$obj
            .receive(on: RunLoop.main).sink { o in
              // NSLog("@@@@ Updating list \(self.name) with object change \(o)\n\n")
              self.list = self.list.map { ele in
                if ele.id == o?.id {
                  return o!
                } else {
                  return ele
                }
              }
          }
        case .delete :
          let index = list.firstIndex { d in
            d.id == input.subject
          }
          if index != nil {
            self.list.remove(at: index!)
          }
          self.objCancels[input.subject]?.cancel()
          self.objCancels[input.subject] = nil
          self.objAggs.removeValue(forKey: input.subject)
        case .move(let from, let after, _) :
          let e = self.find(id: from)
          if e != nil {
            let fromIndex = list.firstIndex { d in
              d.id == from
            }
            let afterIndex = list.firstIndex { d in
              d.id == after
              } ?? -1
            if fromIndex != nil {
              list.remove(at: fromIndex!)
              if fromIndex! < afterIndex {
                list.insert(e!, at: afterIndex)
              } else {
                list.insert(e!, at: afterIndex+1)
              }
            }
          }
      }
    }
    return Subscribers.Demand.unlimited
  }
  
  public func receive(completion: Subscribers.Completion<Never>) {
    sub?.cancel()
    sub = nil
  }
}
