//
//  EventToFileLogger.swift
//  Ladi
//
//  Created by Michael Latta on 12/2/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine
import SwiftUI


@available(iOS 14.0, macOS 11.0, *)
class FileLogSubscription<S> : Subscription where S : Subscriber, S.Input == Event {
  var id = UUID()
  var subscriber : S?
  var log : EventToFileLogger
  var index = 0
  var remaining : Int?
  
  init(subscriber: S, log : EventToFileLogger) {
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

@available(iOS 14.0, macOS 11.0, *)
open class EventToFileLogger : Publisher {
  public typealias Output = Event
  public typealias Input = Event?
  public typealias Failure = Never
  
  static var queue = DispatchQueue(label: "event_log")
  public var docDirectory : URL?
  public var path : URL?
  public var created : Bool = false
  private static var counter : Int = 0
  private var loadedProjects : [UUID] = []
  var downStream : Subscription? = nil
  public var events : [Event] = []
  public var savedEvents = Set<UUID>()
  
  public init?() {
    guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    docDirectory = documentsDirectory
    let fileName = "events.log"
    path = documentsDirectory.appendingPathComponent(fileName)
    guard path != nil else { return nil}
    if !FileManager.default.fileExists(atPath: path!.path) {
      self.created = true
      FileManager.default.createFile(atPath: path!.path, contents: nil)
    }
  }
  
  public func receive(subscription: Subscription) {
    subscription.request(Subscribers.Demand.unlimited)
  }
  
  public func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, Event == S.Input {
    //    NSLog("@@@@ Subscription to log by \(subscriber) with \(downStreams.count) subscriptions current")
    let sub : FileLogSubscription<S> = FileLogSubscription<S>(subscriber: subscriber, log: self)
    downStream = sub
    subscriber.receive(subscription: sub)
  }
  
  public func subscribe(to log: EventLog) -> AnyCancellable {
    return log.receive(on: EventToFileLogger.queue)
      .sink { e in
        do {
          EventToFileLogger.counter += 1
          if !self.savedEvents.contains(e.id) {
            self.events.append(e)
            self.savedEvents.insert(e.id)
            self.downStream?.request(Subscribers.Demand.unlimited)
            var fileHandle : FileHandle?
            if e.project == e.subject {
              fileHandle = try? FileHandle(forWritingTo: self.path!)
            } else {
              let path = self.docDirectory!.appendingPathComponent(e.project.uuidString)
              if !FileManager.default.fileExists(atPath: path.path) {
                FileManager.default.createFile(atPath: path.path, contents: nil)
              }
              fileHandle = try? FileHandle(forWritingTo: path)
            }
            var e2 = e
            e2.status = .persisted
//            Swift.print("@@@@ Logging event: \(e)")
            guard fileHandle != nil else {return}
            let data : Data = try e2.encode()
            fileHandle?.seekToEndOfFile()
            let typeName : String? = TypeTracker.keyFromType(type(of: e2))!
            if typeName == nil || TypeTracker.typeFromKey(typeName!) == nil {
              NSLog("\n\n\n#####\n##### Failed to register type \(typeName ?? "nil")\n#####\n\n\n")
              ErrTracker.log(Err(msg: "Coding Error",
                                 details: "Failed to register type \(typeName ?? "nil")"))
            }
            fileHandle!.write(typeName!.data(using: .utf8)!)
            fileHandle!.write("\n".data(using: .utf8)!)
            fileHandle!.write(data)
            fileHandle!.write("\n".data(using: .utf8)!)
            fileHandle!.closeFile()
          }
        } catch {
          NSLog("#### Error in handling event log to file \(error)")
          ErrTracker.log(Err(msg: "Error saving data to local storage",
                             details: "\(error)"))
        }
      }
  }

  /// load events from the log file if it exists and has content, return true if events were actually loaded
  
  @discardableResult public func loadEvents(store: UndoableEventStore, progress: Progress, showLoading: LoadingStatus, onComplete: @escaping (_ : Loading) -> Void) -> Loading {
    return loadEvents(url: self.path!, store: store, progress: progress, showLoading: showLoading, onComplete: onComplete)
  }
  @discardableResult public func loadEvents(for project: UUID, store: UndoableEventStore, progress: Progress, showLoading: LoadingStatus, onComplete: @escaping (_ : Loading) -> Void) -> Loading {
    guard !self.loadedProjects.contains(project) else {
      return .loadingFile
    }
    self.loadedProjects.append(project)
    let projectPath = self.docDirectory!.appendingPathComponent(project.uuidString)
    return loadEvents(url: projectPath, store: store, progress: progress, showLoading: showLoading, onComplete: onComplete)
  }
  @discardableResult public func loadEvents(url: URL, store: UndoableEventStore, progress:Progress, showLoading: LoadingStatus, onComplete: @escaping (_ : Loading) -> Void) -> Loading {
    let fileHandle = try? FileHandle(forReadingFrom: url)
    guard fileHandle != nil else {
      onComplete(.newFile)
      return .newFile
    }
    DispatchQueue.main.async {
      showLoading.loading = .loading
      progress.total = 100 // placeholder to keep it up until we have a real count
    }
    DispatchQueue.global(qos: .background).async {
      NSLog("@@@@ Reading events from file: "+url.path)
      fileHandle!.seek(toFileOffset:0)
      let data = fileHandle!.readDataToEndOfFile()
      let str = String(data: data, encoding: .utf8)!
      let events = str.components(separatedBy: "\n")
      NSLog("@@@@ Found \(events.count) lines read from file")
      var evts = [Event]()
      for i in stride(from: 0, to: events.count-1, by: 2) {
        let typeName = events[i]
        let json = events[i+1]
        let et : Event.Type = TypeTracker.typeFromKey(typeName) as! Event.Type
        do {
          var event : Event = try et.decode(from: json.data(using: .utf8)!)
          event.status = .cached
          evts.append(event)
        } catch {
          NSLog("#### Error \(error) in loading event \(typeName) \(json)")
          ErrTracker.log(Err(msg: "Coding Error",
                             details: "Error \(error) in loading event \(typeName) \(json)"))
        }
      }
      NSLog("@@@@ \(evts.count) Events decoded")
      DispatchQueue.main.async {
        NSLog("@@@@ Setting progress total to \(evts.count)")
        progress.total = evts.count
//        NSLog("@@@@ Showing loading screen")
//        showLoading.loading = true
        progress.progress = 0
      }
      if evts.count > 0 {
        self.processEvent(evts, 0, store: store, progress: progress, showLoading: showLoading, onComplete: onComplete)
      } else {
        DispatchQueue.main.async {
          NSLog("@@@@ No Events loaded")
          showLoading.loading = .done
          onComplete(.loadingFile)
        }
      }
    }
    return .startLoadingFile
  }
  
  func processEvent(_ events:[Event], _ i:Int, store: UndoableEventStore, progress:Progress, showLoading: LoadingStatus, onComplete: @escaping (_ : Loading) -> Void) {
    DispatchQueue.main.async { [self] in
      let limit = Swift.min(i+100, events.count)
//      NSLog("@@@@ Loading events \(i) to \(limit)")
      for ind in i ..< limit {
        savedEvents.insert(events[ind].id)
        Swift.print("@@@@ Loading event: \(String(describing: events[ind]))")
        store.append(events[ind])
      }
//      NSLog("@@@@ Setting progress to \(limit)")
      progress.progress = limit
      if limit < events.count {
        self.processEvent(events, limit, store: store, progress: progress, showLoading: showLoading, onComplete: onComplete)
      } else {
        NSLog("@@@@ Events loaded")
        showLoading.loading = .done
        onComplete(.loadingFile)
      }
    }
  }
}
