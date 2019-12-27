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
  
  public required init() {
    
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
  
  public func delete(project: UUID, indices: IndexSet) {
    for i in indices {
      let field = self.list[i]
      let e = ListChange<E,R>(project: project, subject: field.id,
        action: .delete(at: i, obj: field))
      self.store?.append(e)
    }
  }
  
  public func move(project: UUID, from: IndexSet, to: Int) {
    for f in from {
      let item = self.list[f]
      let e = ListChange<E,R>(project: project, subject: item.id,
        action: .move(from: f, to: min(to, self.list.count)))
      self.store?.append(e)
    }
  }
  
  public func delete(project: UUID, indices: IndexSet, in parent : UUID, role: R) {
    for i in indices {
      let field = self.list[i]
      let e = ListChange<E,R>(project: project, subject: field.id,
                              action: .delete(at: i, obj: field),
                              parent: parent, role: role)
      self.store?.append(e)
    }
  }
  
  public func move(project: UUID, from: IndexSet, to: Int, in parent: UUID, role: R) {
    for f in from {
      let item = self.list[f]
      let e = ListChange<E,R>(project: project, subject: item.id,
                              action: .move(from: f, to: min(to, self.list.count)),
                              parent: parent, role: role)
      self.store?.append(e)
    }
  }
  
  public func receive(subscription: Subscription) {
    sub = subscription
    subscription.request(Subscribers.Demand.unlimited)
  }
  
  public func filterEvent(_ input: LE) -> Bool {
    guard !self.events.contains(where: { e in e.id == input.id}) else {return false}
//    NSLog("\n\n@@@@ Filter list event \(input) for role: \(role) in \(name)\n\n")
    guard self.role == nil || self.role == input.role else {return false}
    guard self.filter != nil else {return true}
    return self.filter!(input)
  }
  
  public func receive(_ input: LE) -> Subscribers.Demand {
    if self.filterEvent(input) {
      events.append(input)
      switch input.action {
        case .create(let at, let obj) :
//           NSLog("\n\n@@@@ Inserting object in \(name) \(role) of \(parent) list \(obj) has child config: \(self.childConfig != nil)\n\n")
          let oa = self.childConfig?(store!, self, obj) ??
            ObjectAggregator<E,R>(obj: obj, store: self.store) { e in e.subject == obj.id}
          // NSLog("@@@@ Child aggregator has children: \(oa.childAggregators)")
          oa.store = self.store
          self.store?.log.subscribe(oa)
          self.objAggs[obj.id] = oa
          self.list.insert(obj, at: at)
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
        case .move(let f, let t) :
          let e = list[f]
          list.remove(at: f)
          list.insert(e, at: t)
      }
    }
    return Subscribers.Demand.unlimited
  }
  
  public func receive(completion: Subscribers.Completion<Never>) {
    sub?.cancel()
    sub = nil
  }
}
