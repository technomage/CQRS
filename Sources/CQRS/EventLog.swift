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

@available(iOS 13.0, *)
class LogSubscription<S> : Subscription where S : Subscriber, S.Input == Event {
  var id = UUID()
  var subscriber : S?
  var log : EventLog
  var index = 0
  var remaining : Int?
  
  init(subscriber: S, log : EventLog) {
    self.subscriber = subscriber
    self.log = log
  }
  
  func request(_ demand: Subscribers.Demand) {
    var d = demand
    if let sub = subscriber {
      while (d.max == nil || d.max! > 0) && index < log.events.count {
        index += 1
        let event = log.events[index-1]
//        NSLog("@@@@ Sending \(index) \(id) to \((sub as? DebugNamed)?.name ?? String(describing: sub)) for event \(event)\n\n")
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

@available(iOS 13.0, *)
public class EventLog : Subscriber, Publisher {
  public typealias Output = Event
  public typealias Input = Event?
  public typealias Failure = Never
  
  var downStreams : [Subscription] = []
  var upStream : Subscription?
  var events : Events = []
  
  public func receive<S>(subscriber: S) where S : Subscriber, EventLog.Failure == S.Failure, EventLog.Output == S.Input {
//    NSLog("@@@@ Subscription to log by \(subscriber) with \(downStreams.count) subscriptions current")
    let subs : LogSubscription<S> = LogSubscription<S>(subscriber: subscriber, log: self)
    downStreams.append(subs)
    subscriber.receive(subscription: subs)
  }
  
  public func receive(subscription: Subscription) {
    upStream = subscription
    subscription.request(Subscribers.Demand.unlimited)
  }
  
  public func receive(_ input: Event?) -> Subscribers.Demand {
    if let inp = input {
      var evt = inp
      if evt.status == .new {
        evt.status = .queued
      }
      events.append(evt)
      // The following feels like a kludge, since we do not know how much
      // demand is remaining
      for ds in downStreams {
        ds.request(Subscribers.Demand.unlimited)
      }
    }
    return Subscribers.Demand.unlimited;
  }
  
  public func receive(completion: Subscribers.Completion<Never>) {
    upStream?.cancel()
    upStream = nil
  }
}
