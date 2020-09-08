//
//  ObjectAggregator.swift
//  Ladi
//
//  Created by Michael Latta on 10/4/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

@available(iOS 13.0, macOS 10.15, *)
public typealias FilterClosure = (Event) -> Bool

@available(iOS 13.0, macOS 10.15, *)
open class ObjectAggregator<E : Codable, R : Hashable&Codable> : Subscriber, Identifiable, Aggregator, ObservableObject
  where E : Identifiable, E.ID == UUID
{
  public typealias Input = Event
  public typealias Failure = Never
  
  public var id = UUID()
  public var subject : UUID
  @Published public var obj : E?
  @Published public var events : [Event] = []
  public var eventIds : Set<UUID> = []
  var sub : Subscription?
  public var store : UndoableEventStore?
  @Published public var childAggregators : [R:Aggregator] = [:]
  
  public convenience init(store: UndoableEventStore?, subject: UUID) {
    self.init(subject: subject)
    self.store = store
    guard store != nil else {return}
    store!.log.subscribe(self)
  }
  
  public init(subject: UUID) {
    self.subject = subject
  }
  public convenience init(obj: E) {
    self.init(subject: obj.id)
    self.obj = obj
  }
  
  public convenience init(obj: E, store: UndoableEventStore?) {
    self.init(store: store, subject: obj.id)
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
    return !self.eventIds.contains(input.id) && input.subject == self.subject
  }
  
  public func receive(_ input: Event) -> Subscribers.Demand {
    if self.test(input) {
      if let evt = input as? ListChange<E,R> {
//        NSLog("@@@@ List event applied to object aggregator \(input) agg id: \(self.id)")
        events.append(evt)
        eventIds.insert(evt.id)
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

