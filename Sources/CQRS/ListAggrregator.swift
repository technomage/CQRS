//
//  ListAggrregator.swift
//  Ladi
//
//  Created by Michael Latta on 10/4/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

protocol ListEntry : Equatable, Codable {
  var id : UUID { get }
}

protocol NamedListEntry : ListEntry {
  var name : String { get set }
}

@available(iOS 13.0, *)
class ListAggregator<E : ListEntry, R : Hashable&Codable> : Subscriber, ObservableObject, Aggregator { typealias Input = ListChange<E,R>
  typealias Failure = Never
  typealias LE = ListChange<E,R>
  typealias ListFilterClosure = (LE) -> Bool
  typealias ChildAggregatorClosure = (_ store: UndoableEventStore, _ par : ListAggregator<E,R>, _ obj: E) -> ObjectAggregator<E,R>
  
  var role : R?
  var filter : ListFilterClosure?

  @Published var list : [E] = []
  @Published var events : [LE] = []
  var sub : Subscription?
  var store : UndoableEventStore?
  var childConfig : ChildAggregatorClosure?
  var objAggs = Dictionary<UUID, ObjectAggregator<E,R>>()
  var objCancels = Dictionary<UUID, AnyCancellable>()
  var parent : UUID?
  var name : String?
  
  required init() {
    
  }
  
  convenience init(filter: @escaping ListFilterClosure) {
    self.init()
    self.filter = filter
  }
  
  convenience init(config : @escaping ChildAggregatorClosure) {
    self.init()
    self.childConfig = config
  }
  
  convenience init(config : @escaping ChildAggregatorClosure,
                   filter: @escaping ListFilterClosure) {
    self.init()
    self.childConfig = config
    self.filter = filter
  }
  
  convenience init(role: R) {
    self.init()
    self.role = role
  }
  
  convenience init(role: R, store: UndoableEventStore) {
    self.init()
    self.role = role
    self.store = store
    self.subscribeToStore()
  }
  
  convenience init(role: R, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
  }
  
  convenience init(role: R, store: UndoableEventStore, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
    self.store = store
    self.subscribeToStore()
  }
  
  convenience init(role: R, store: UndoableEventStore, parent: UUID, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
    self.parent = parent
    self.store = store
    self.subscribeToStore()
  }
  
  convenience init(role: R, store: UndoableEventStore, parent: UUID, config: @escaping ChildAggregatorClosure, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
    self.childConfig = config
    self.parent = parent
    self.store = store
    self.subscribeToStore()
  }
  
  convenience init(role: R, config : @escaping ChildAggregatorClosure) {
    self.init()
    self.role = role
    self.childConfig = config
  }
  
  convenience init(store : UndoableEventStore) {
    self.init()
    self.store = store
    self.subscribeToStore()
  }
  
  convenience init(store : UndoableEventStore, filter: @escaping ListFilterClosure) {
    self.init(store: store)
    self.filter = filter
  }
  
  func subscribeToStore() {
    guard self.store != nil else {return}
    self.store!.log
      .filter({e in e is ListChange<E,R>})
      .map{e in e as! ListChange<E,R>}
      .subscribe(self)
  }
  
  func setName(_ name : String) -> Self {
    self.name = name
    return self
  }
  
  func delete(project: UUID, indices: IndexSet, in parent : UUID?, role: R?) {
    for i in indices {
      let field = self.list[i]
      let e = ListChange<E,R>(project: project, subject: field.id,
        action: .delete(at: i, obj: field),
        parent: parent, role: role)
      self.store?.append(e)
    }
  }
  
  func move(project: UUID, from: IndexSet, to: Int, in parent: UUID?, role: R? ) {
    for f in from {
      let item = self.list[f]
      let e = ListChange<E,R>(project: project, subject: item.id,
        action: .move(from: f, to: min(to, self.list.count)),
        parent: parent, role: role)
      self.store?.append(e)
    }
  }
  
  func receive(subscription: Subscription) {
    sub = subscription
    subscription.request(Subscribers.Demand.unlimited)
  }
  
  func filterEvent(_ input: LE) -> Bool {
    guard !self.events.contains(where: { e in e.id == input.id}) else {return false}
//    NSLog("\n\n@@@@ Filter list event \(input) for role: \(role) in \(name)\n\n")
    guard self.role == nil || self.role == input.role else {return false}
    guard self.filter != nil else {return true}
    return self.filter!(input)
  }
  
  func receive(_ input: LE) -> Subscribers.Demand {
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
  
  func receive(completion: Subscribers.Completion<Never>) {
    sub?.cancel()
    sub = nil
  }
}
