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
open class ObjectAggregator<E : WithID&Equatable, R : Hashable&Codable&RoleEnum> : Subscriber, EventSubscriber, Identifiable, Aggregator, ObservableObject, DispatchKeys where E : Identifiable, E.ID == UUID
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
  
  public var dispatchKeys : [String]? {
    return [subject.uuidString]
  }
  
  public func receive(subscription: Subscription) {
    sub = subscription
    subscription.request(Subscribers.Demand.unlimited)
  }
  
  public func subscribeToStore() {
    guard self.store != nil else {return}
    self.store!.log.subscribe(self)
  }
  
  // The following MUST be overridden for any aggregator that has child lists
  open func configureChildren() {
  }
  
  public func test(_ input : Event) -> Bool {
    return !self.eventIds.contains(input.id) && input.subject == self.subject
  }

  open func receive(event: Event) {
    if self.test(event) {
      if let evt = event as? ListChange<E,R> {
        self.events.append(evt)
        self.eventIds.insert(evt.id)
        switch evt.action {
          case .create(_, let o) :
            self.obj = o
          case .delete :
            self.obj = nil
          default:
            break
        }
      }
      if let o = self.obj, let evt = event as? ObjectEvent {
        self.events.append(evt)
        self.eventIds.insert(evt.id)
        self.obj = evt.apply(to: o)
      }
    }
  }
  
  public func receive(_ input: Event) -> Subscribers.Demand {
    receive(event: input)
    return Subscribers.Demand.unlimited
  }
  
  public func receive(completion: Subscribers.Completion<Never>) {
    sub?.cancel()
    sub = nil
  }
}

