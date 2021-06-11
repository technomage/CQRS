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
  
  /// MARKER: Backups
  
  /// Perform a full backup of all internal projects
  public func fullBackup(projectNames: [UUID:String]) throws {
    guard let docPath = docDirectory?.path else {return}
    guard let iCloudDocs = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") else {return}
    let tmp = FileWrapper(regularFileWithContents: "Testing".data(using: .utf8)!)
    try tmp.write(to: iCloudDocs.appendingPathComponent("Test.txt"), originalContentsURL: nil)
    let data = "No File Wrapper".data(using: .utf8)
    try data?.write(to: iCloudDocs.appendingPathComponent("testNoFW.txt"))
    let paths = try FileManager.default.contentsOfDirectory(atPath: docPath)
    for p in paths {
      Swift.print("@@@@ Path: \(p)")
      if p.hasSuffix(".ladi") {
        if let docURL = docDirectory?.appendingPathComponent(p) {
          let efw = try FileWrapper(url: docURL.appendingPathComponent("events"),
                                    options: .immediate)
          let fw = FileWrapper(directoryWithFileWrappers: ["events":efw])
          let proj = p.replacingOccurrences(of: ".ladi", with: "")
          let pid = UUID(uuidString: proj)
          let projectName = pid != nil ? projectNames[pid!] ?? proj : proj
          Swift.print("@@@@ project name \(projectName)")
          let bk = iCloudDocs.appendingPathComponent(projectName+".ladi")
          Swift.print("@@@@ backup path \(bk)")
          try fw.write(to: bk,
                       options: [.withNameUpdating,.atomic],
                       originalContentsURL: nil)
        }
      }
    }
    Swift.print("")
  }
  
  /// MARKER: Attachment Support
  
  public func saveAttachmentContent(project: UUID, id: UUID, file: NSData) throws {
    try saveAttachmentContent(project: project, id: id, data: file, ext: nil)
  }
  
  public func saveAttachmentContent(project: UUID, id: UUID, image: NSData) throws {
    try saveAttachmentContent(project: project, id: id, data: image, ext: "jpeg")
//    try saveAttachmentContent(project: project, id: id, data: image, ext: "png")
  }
  
  public func saveAttachmentContent(project: UUID, id: UUID, video: NSData) throws {
    try saveAttachmentContent(project: project, id: id, data: video, ext: "m4p")
  }
  
  public func saveAttachmentContent(project: UUID, name: String, data: Data) throws {
    var path = self.docDirectory!
      .appendingPathComponent(project.uuidString+".ladi")
    if !FileManager.default.fileExists(atPath: path.path) {
      try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }
    path = path.appendingPathComponent(name)
    print("@@@@ Saving attachment to \(path)")
    if !FileManager.default.fileExists(atPath: path.path) {
      FileManager.default.createFile(atPath: path.path, contents: data as Data)
    } else {
      FileManager.default.createFile(atPath: path.path, contents: nil)
      let file = try? FileHandle(forWritingTo: path)
      file?.write(data as Data)
    }
  }
  
  public func saveAttachmentContent(project: UUID, id: UUID, data: NSData, ext: String?) throws {
    let extra = ext == nil ? "" : ".\(ext!)"
    var path = self.docDirectory!
      .appendingPathComponent(project.uuidString+".ladi")
    if !FileManager.default.fileExists(atPath: path.path) {
      try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }
    path = path.appendingPathComponent(id.uuidString+extra)
    print("@@@@ Saving attachment to \(path)")
    if !FileManager.default.fileExists(atPath: path.path) {
      FileManager.default.createFile(atPath: path.path, contents: data as Data)
    } else {
      FileManager.default.createFile(atPath: path.path, contents: nil)
      let file = try? FileHandle(forWritingTo: path)
      file?.write(data as Data)
    }
  }
  
  public func readFileAttachmentContent(project: UUID, id: UUID) throws -> Data? {
    try readAttachmentContent(project: project, id: id, ext: nil)
  }
  
  public func readImageAttachmentContent(project: UUID, id: UUID) throws -> Data? {
//    try readAttachmentContent(project: project, id: id, ext: "png")
    try readAttachmentContent(project: project, id: id, ext: "jpeg")
  }
  
  public func readVideoAttachmentContent(project: UUID, id: UUID) throws -> Data? {
    try readAttachmentContent(project: project, id: id, ext: "m4p")
  }
  
  public func readAttachmentContent(project: UUID, id: UUID, ext: String?) throws -> Data? {
    let extra = ext == nil ? "" : ".\(ext!)"
    let path = self.docDirectory!
      .appendingPathComponent(project.uuidString+".ladi")
      .appendingPathComponent(id.uuidString+extra)
    if FileManager.default.fileExists(atPath: path.path) {
      let file = FileHandle(forReadingAtPath: path.path)
      return try file?.readToEnd()
    } else {
      return nil
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
            if e.project == e.subject {
              let fileHandle = try? FileHandle(forWritingTo: self.path!)
              try self.saveEventToFile(file: fileHandle, event: e)
            }
            var path = self.docDirectory!
              .appendingPathComponent(e.project.uuidString+".ladi")
            if !FileManager.default.fileExists(atPath: path.path) {
              try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
              path = path.appendingPathComponent("events")
              FileManager.default.createFile(atPath: path.path, contents: nil)
            } else {
              path = path.appendingPathComponent("events")
            }
            Swift.print("@@@@ Writing event to file: \(path)")
            let file = try? FileHandle(forWritingTo: path)
            try self.saveEventToFile(file: file, event: e)
          }
        } catch {
          Swift.print("#### Error in handling event log to file \(error)")
          ErrTracker.log(Err(msg: "Error saving data to local storage",
                             details: "\(error)"))
        }
      }
  }
  
  func saveEventToFile(file: FileHandle?, event: Event) throws {
    var e2 = event
    e2.status = .persisted
    guard file != nil else {return}
    let data : Data = try e2.encode()
    file?.seekToEndOfFile()
    let typeName : String? = TypeTracker.keyFromType(type(of: e2))!
    if typeName == nil || TypeTracker.typeFromKey(typeName!) == nil {
      Swift.print("\n\n\n#####\n##### Failed to register type \(typeName ?? "nil")\n#####\n\n\n")
      ErrTracker.log(Err(msg: "Coding Error",
                         details: "Failed to register type \(typeName ?? "nil")"))
    }
    file!.write(typeName!.data(using: .utf8)!)
    file!.write("\n".data(using: .utf8)!)
    file!.write(data)
    file!.write("\n".data(using: .utf8)!)
    file!.closeFile()
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
    let projectPath = self.docDirectory!
      .appendingPathComponent(project.uuidString+".ladi")
      .appendingPathComponent("events")
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
      Swift.print("@@@@ Reading events from file: "+url.path)
      fileHandle!.seek(toFileOffset:0)
      let data = fileHandle!.readDataToEndOfFile()
      let str = String(data: data, encoding: .utf8)!
      let events = str.components(separatedBy: "\n")
      perfMsg("Loading \(events.count/2) events")
//      print("@@@@ Found \(events.count) lines read from file")
      var evts = [Event]()
      for i in stride(from: 0, to: events.count-1, by: 2) {
        let typeName = events[i]
        let json = events[i+1]
//        if json.hasPrefix("|") {
//          continue;
//        }
//          let uuid = String(json.split(separator: "|")[0])
//          json = self.readAttachment(uuid)
//        }
//        Swift.print("@@@@ Loading event from file \(typeName): \(json)")
        let et : Event.Type = TypeTracker.typeFromKey(typeName) as! Event.Type
        do {
          var event : Event = try et.decode(from: json.data(using: .utf8)!)
          event.status = .cached
          evts.append(event)
        } catch {
          Swift.print("#### Error \(error) in loading event \(typeName) \(json)")
          ErrTracker.log(Err(msg: "Coding Error",
                             details: "Error \(error) in loading event \(typeName) \(json)"))
        }
      }
//      NSLog("@@@@ \(evts.count) Events decoded")
      DispatchQueue.main.async {
//        NSLog("@@@@ Setting progress total to \(evts.count)")
        progress.total = evts.count
//        NSLog("@@@@ Showing loading screen")
//        showLoading.loading = true
        progress.progress = 0
      }
      if evts.count > 0 {
        self.processEvent(evts, 0, store: store, progress: progress, showLoading: showLoading, onComplete: onComplete)
      } else {
        DispatchQueue.main.async {
//          NSLog("@@@@ No Events loaded")
//          showLoading.loading = .done
          onComplete(.loadingFile)
        }
      }
    }
    return .startLoadingFile
  }
  
  func readAttachment(_ fn : String) -> String {
    guard let documentsDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
    else { return "" }
    docDirectory = documentsDirectory
    path = documentsDirectory.appendingPathComponent(fn)
    guard path != nil else { return ""}
    let fileHandle = try? FileHandle(forReadingFrom: path!)
    if fileHandle == nil {
      Swift.print("#### Failed to read attachment")
      return ""
    } else {
      let data = fileHandle!.readDataToEndOfFile()
      return String(data: data, encoding: .utf8)!
    }
  }
  
  func writeAttachment(_ fn: String, json: Data) {
    guard let documentsDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
    else { return }
    docDirectory = documentsDirectory
    path = documentsDirectory.appendingPathComponent(fn)
    guard path != nil else { return }
    FileManager.default.createFile(atPath: path!.path, contents: nil)
    let fileHandle = try? FileHandle(forWritingTo: path!)
    if fileHandle == nil {
      Swift.print("#### Failed to write attachment")
    } else {
      fileHandle!.write(json)
    }
  }
  
  func processEvent(_ events:[Event], _ i:Int, store: UndoableEventStore,
                    progress:Progress, showLoading: LoadingStatus,
                    onComplete: @escaping (_ : Loading) -> Void) {
    let limit = Swift.min(i+100, events.count)
    EventToFileLogger.queue.async {
      for ind in i ..< limit {
        self.savedEvents.insert(events[ind].id)
      }
    }
    DispatchQueue.main.async {
      for ind in i ..< limit {
//        Swift.print("@@@@ Loaded event: \(events[ind])")
        store.append(events[ind])
      }
//      NSLog("@@@@ Setting progress to \(limit)")
      progress.progress = limit
      if limit < events.count {
        self.processEvent(events, limit, store: store, progress: progress, showLoading: showLoading, onComplete: onComplete)
      } else {
//        NSLog("@@@@ Events loaded")
//        showLoading.loading = .done
        onComplete(.loadingFile)
      }
    }
  }
}
