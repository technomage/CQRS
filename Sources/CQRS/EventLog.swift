//
//  EventLog.swift
//  Ladi
//
//  Created by Michael Latta on 9/26/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

public protocol DebugNamed {
  var name : String { get }
}

@available(iOS 14.0, macOS 11.0, *)
public protocol EventSubscriber {
  func receive(event:Event)
  var id : UUID {get}
}

public protocol EventSubscription : Subscription {
  var eventSubscriber : EventSubscriber? {get}
}

@available(iOS 14.0, macOS 11.0, *)
class LogSubscription<S> : EventSubscription where S : Subscriber, S.Input == Event {
  var id = UUID()
  var subscriber : S?
  var log : EventLog
  var index = 0
  var remaining : Int?
  
  init(subscriber: S, log : EventLog) {
    self.subscriber = subscriber
    self.log = log
  }
  
  var eventSubscriber : EventSubscriber? {
    subscriber as? EventSubscriber
  }
  
  func request(_ demand: Subscribers.Demand) {
    var d = demand
    if let sub = subscriber {
      while (d.max == nil || d.max! > 0) && index < log.events.count {
        index += 1
        let event = log.events[index-1]
//        print("@@@@ Sending event to subscriber \(event)")
        if UndoableEventStore.debugUndo && UndoableEventStore.seenRedo {
//          print("@@@@ Sending \(index)/\(log.events.count) \(id) to \((sub as? DebugNamed)?.name ?? String(describing: sub)) for event \(String(describing: event))\n\n")
        }
        let d2 = sub.receive(event)
        if (d.max != nil && d2.max != nil) {
          d = Subscribers.Demand.max(d.max! + d2.max!)
        }
      }
      remaining = d.max
    }
  }
  
  func cancel() {
    subscriber = nil
  }
}

public protocol DispatchKeys {
  var dispatchKeys : [String]? { get }
}

@available(iOS 14.0, macOS 11.0, *)
open class EventLog : Subscriber, Publisher {
  public typealias Output = Event
  public typealias Input = Event?
  public typealias Failure = Never
  
  var downStreams : [Subscription] = []
  var dsKeyed : [String:[Subscription]] = [:]
  var upStream : Subscription?
  public var events : Events = []
  
  public init() {
//    Swift.print("@@@@ Creating EventLog")
  }
  
  public func receive<S>(subscriber: S) where S : Subscriber, EventLog.Failure == S.Failure, EventLog.Output == S.Input {
    perfStart("EventLog received event subscriber")
//    NSLog("@@@@ Subscription to log by \(subscriber) with \(downStreams.count) subscriptions current")
    let sub : LogSubscription<S> = LogSubscription<S>(subscriber: subscriber, log: self)
    if subscriber is DispatchKeys {
      let keys = (subscriber as! DispatchKeys).dispatchKeys
      if keys != nil {
        for k in keys! {
          var subs = dsKeyed[k] ?? []
          for s in subs {
            if let su = s as? EventSubscription, let subscr = subscriber as? EventSubscriber,
               su.eventSubscriber?.id == subscr.id {
              Swift.print("#### Found subscriber already subscribed")
            }
          }
          subs.append(sub)
          dsKeyed[k] = subs
//          Swift.print("\n\n@@@@ Registring dispatch key subscriber \(String(describing: k)): \(sub) subs: \(subs.count) dsKeyed: \(dsKeyed[k])\n\n")
        }
      } else {
        downStreams.append(sub)
      }
    } else {
      downStreams.append(sub)
    }
    subscriber.receive(subscription: sub)
    perfEnd("EventLog received event subscriber")
  }
  
  public func receive(subscription: Subscription) {
    upStream = subscription
    subscription.request(Subscribers.Demand.unlimited)
  }
  
  public func receive(_ input: Event?) -> Subscribers.Demand {
    perfStart("EventLog received event")
//    Swift.print("\n\n\n@@@@ Dispatching event \(input) with dsKeyed: \(dsKeyed)\n\n")
    if let inp = input {
      var evt = inp
      if evt.status == .new {
        evt.status = .queued
      }
      events.append(evt)
//      Swift.print("@@@@ Event \(inp.id.uuidString) received by log")
      // The following feels like a kludge, since we do not know how much
      // demand is remaining
      for ds in downStreams {
        if ds is EventSubscriber {
//          Swift.print("@@@@   Dispatching directly to \(type(of: ds)) \(ds)")
          (ds as! EventSubscriber).receive(event: inp)
        } else if let dss = ds as? EventSubscription, let sub = dss.eventSubscriber {
//          Swift.print("@@@@  Dispatching directly to subscriber \(type(of: sub))")
          sub.receive(event: inp)
        } else {
//          Swift.print("@@@@   Dispatching indirectly to \(type(of: ds)) \(ds)")
          ds.request(Subscribers.Demand.unlimited)
        }
      }
      if inp is DispatchKeys {
        let keys = (inp as! DispatchKeys).dispatchKeys
//        Swift.print("@@@@ Dispatching event \(inp) for keys: \(String(describing: keys))")
        for k in keys ?? [] {
//          Swift.print("@@@@    DsKeys for event \(k): \(dsKeyed[k])")
          for ds in dsKeyed[k] ?? [] {
            if ds is EventSubscriber {
//              Swift.print("@@@@   Dispatching directly to \(type(of: ds)) \(ds)")
              (ds as! EventSubscriber).receive(event: inp)
            } else if let dss = ds as? EventSubscription, let sub = dss.eventSubscriber {
//              Swift.print("@@@@  Dispatching directly to subscriber \(type(of: sub))")
              sub.receive(event: inp)
            } else {
//              Swift.print("@@@@   Dispatching indirectly to \(type(of: ds)) \(ds)")
              ds.request(Subscribers.Demand.unlimited)
            }
          }
        }
      }
    }
    perfEnd("EventLog received event")
    return Subscribers.Demand.unlimited;
  }
  
  public func receive(completion: Subscribers.Completion<Never>) {
    upStream?.cancel()
    upStream = nil
  }
}
