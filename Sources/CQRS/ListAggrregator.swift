//
//  ListAggrregator.swift
//  Ladi
//
//  Created by Michael Latta on 10/4/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

public protocol ListEntry : Equatable, WithID {
}

public protocol NamedListEntry : ListEntry {
  var name : String { get set }
}

public protocol RoleEnum {
  var rawValue : String { get }
}

@available(iOS 13.0, macOS 10.15, *)
open class ListAggregator<E : ListEntry, R : Hashable&Codable&RoleEnum> : Subscriber, Identifiable, ObservableObject, Aggregator, DispatchKeys where E : Identifiable, E.ID == UUID
{
  public typealias Input = Event
  public typealias Failure = Never
  public typealias LE = ListChange<E,R>
  public typealias ListFilterClosure = (LE) -> Bool
  public typealias ChildAggregatorClosure = (_ store: UndoableEventStore, _ par : ListAggregator<E,R>, _ obj: E) -> ObjectAggregator<E,R>
  
  public var role : R?
  public var filter : ListFilterClosure?
  public var parent : UUID?

  @Published public var list : [E] = []
  @Published public var events : [LE] = []
  
  private var listOfIDs = [UUID]()
  private var eventIds : Set<UUID> = []
  private var sub : Subscription?
  public var store : UndoableEventStore?
  public var childConfig : ChildAggregatorClosure?
  public var objAggs = Dictionary<UUID, ObjectAggregator<E,R>>()
  var objCancels = Dictionary<UUID, AnyCancellable>()
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
  
  open var dispatchKeys : [String]? {
    return ["\(self.parent?.uuidString ?? "")::\(self.role?.rawValue ?? "")"]
  }
  
  public func subscribeToStore() {
    guard self.store != nil else {return}
    self.store!.log
//      .filter({e in e is ListChange<E,R>})
//      .map{e in e as! ListChange<E,R>}
      .subscribe(self)
  }
  
  public func setName(_ name : String) -> Self {
    self.name = name
    return self
  }
  
  public func indexFor(id : UUID) -> Int? {
    if id == listOfIDs.last {
      return listOfIDs.count-1
    }
    return listOfIDs.firstIndex(of: id)
  }
  
  /// Find the object prior to the obj with the given ID
  public func find(before: UUID) -> E? {
    if let idx = indexFor(id: before) {
      if idx > 0 {
        return self.list[idx-1]
      }
    }
    return nil
  }
  
  /// Find the object after to the obj with the given ID
  public func find(after: UUID) -> E? {
    if let idx = indexFor(id: after) {
      if idx < list.count {
        return self.list[idx+1]
      }
    }
    return nil
  }
  
  /// Locate the object in the list with the given id
  public func find(id: UUID) -> E? {
    if let idx = indexFor(id: id) {
      if idx < list.count {
        return self.list[idx]
      }
    }
    return nil
  }
  
  /// Return the last item in the list
  public var last : E? {
    self.list.last
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
    guard !self.eventIds.contains(input.id) else {return false}
//    NSLog("\n\n@@@@ Filter list event \(input) for role: \(role) in \(name)\n\n")
    guard self.role == nil || self.role == input.role else {return false}
    guard self.filter != nil else {return true}
    return self.filter!(input)
  }
  
  /// For direct receive lists, process one event at a time as provided to the list directly
  public func receive(_ event : Event) -> Subscribers.Demand {
    if event is ListChange<E,R> {
      let le = event as! ListChange<E,R>
      let _ = self.receive(le)
    }
    return Subscribers.Demand.unlimited
  }
  
  /// Receive a new event for the aggregator
  public func receive(_ input: LE) -> Subscribers.Demand {
    if self.filterEvent(input) {
      events.append(input)
      eventIds.insert(input.id)
      switch input.action {
        case .create(let after, let obj) :
//          NSLog("\n\n@@@@ Inserting object in \(String(describing: name)) \(String(describing: role)) of \(String(describing: parent)) list \(obj) has child config: \(self.childConfig != nil)\n\n")
          let oa = self.childConfig?(store!, self, obj) ??
            ObjectAggregator<E,R>(obj: obj, store: self.store)
          // NSLog("@@@@ Child aggregator has children: \(oa.childAggregators)")
          oa.store = self.store
          self.objAggs[obj.id] = oa
          let afterIndex = after == nil ? nil : indexFor(id: after!)
          listOfIDs.insert(obj.id, at: afterIndex != nil ? afterIndex!+1 : 0)
          list.insert(obj, at: afterIndex != nil ? afterIndex!+1 : 0)
          oa.subscribeToStore()
          oa.configureChildren()
          // Track changes to child objects
          self.objCancels[obj.id] = oa.$obj
            .receive(on: RunLoop.main).sink { o in
              // NSLog("@@@@ Updating list \(self.name) with object change \(o)\n\n")
              // TODO: Use index map to update list rather than build a new one?
              self.list = self.list.map { ele in
                if ele.id == o?.id {
                  return o!
                } else {
                  return ele
                }
              }
          }
        case .delete :
          let index = indexFor(id: input.subject)
          if index != nil {
            self.list.remove(at: index!)
            listOfIDs.remove(at: index!)
          }
          self.objCancels[input.subject]?.cancel()
          self.objCancels[input.subject] = nil
          let agg = objAggs[input.subject]
          self.objAggs.removeValue(forKey: input.subject)
          agg?.obj = nil
        case .move(let from, let after, _) :
          let e = self.find(id: from)
          if e != nil {
            let fromIndex = indexFor(id: from)
            let afterIndex = after != nil ? indexFor(id: after!) ?? -1 : -1
            if fromIndex != nil {
              list.remove(at: fromIndex!)
              listOfIDs.remove(at: fromIndex!)
              if fromIndex! < afterIndex {
                list.insert(e!, at: afterIndex)
                listOfIDs.insert(e!.id, at: afterIndex)
              } else {
                list.insert(e!, at: afterIndex+1)
                listOfIDs.insert(e!.id, at: afterIndex+1)
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
