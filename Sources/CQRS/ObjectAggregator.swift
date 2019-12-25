//
//  ObjectAggregator.swift
//  Ladi
//
//  Created by Michael Latta on 10/4/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

public typealias FilterClosure = (Event) -> Bool

@available(iOS 13.0, *)
open class ObjectAggregator<E : Codable, R : Hashable&Codable> : Subscriber, Identifiable, Aggregator, ObservableObject {
  public typealias Input = Event
  public typealias Failure = Never
  
  public var id = UUID()
  public var filter : FilterClosure = { e in true }
  @Published public var obj : E?
  @Published public var events : [Event] = []
  var sub : Subscription?
  public var store : UndoableEventStore?
  public var childAggregators : [R:Aggregator] = [:]
  
  public init() {
    // default init
  }
  
  public init(store: UndoableEventStore?) {
    self.store = store
    guard store != nil else {return}
    store!.log.subscribe(self)
  }
  
  public convenience init(store: UndoableEventStore?, filter: @escaping FilterClosure) {
    self.init(filter: filter)
    self.store = store
    guard store != nil else {return}
    store!.log.subscribe(self)
  }
  
  public convenience init(filter: @escaping FilterClosure) {
    self.init()
    self.filter = filter
  }
  public convenience init(obj: E, filter: @escaping FilterClosure) {
    self.init(filter: filter)
    self.obj = obj
  }
  
  public convenience init(obj: E, store: UndoableEventStore?) {
    self.init(store: store)
    self.obj = obj
  }
  
  public convenience init(obj: E, store: UndoableEventStore?, filter: @escaping FilterClosure) {
    self.init(store: store, filter: filter)
    self.obj = obj
  }
  
  public convenience init(obj: E) {
    self.init()
    self.obj = obj
  }
  
  public func receive(subscription: Subscription) {
    sub = subscription
    subscription.request(Subscribers.Demand.unlimited)
  }
  
  public func subscribeToStore() {
    guard self.store != nil else {return}
    self.store!.log.subscribe(self)
  }
  
  public func test(_ input : Event) -> Bool {
    return !self.events.contains(where: { e in e.id == input.id}) && self.filter(input)
  }
  
  public func receive(_ input: Event) -> Subscribers.Demand {
    if self.test(input) {
      if let evt = input as? ListChange<E,R> {
//        NSLog("@@@@ List event applied to object aggregator \(input) agg id: \(self.id)")
        events.append(evt)
        switch evt.action {
          case .create(_, let o) :
            self.obj = o
          case .delete :
            self.obj = nil
          default:
            break
        }
      }
      if let evt = input as? ObjectEvent {
        events.append(evt)
        self.obj = evt.apply(to: obj)
//        NSLog("@@@@ Updated object in aggregator \(self.obj) for: \(input)\n\n")
      }
    }
    return Subscribers.Demand.unlimited
  }
  
  public func receive(completion: Subscribers.Completion<Never>) {
    sub?.cancel()
    sub = nil
  }
}

