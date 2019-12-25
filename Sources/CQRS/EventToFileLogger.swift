//
//  EventToFileLogger.swift
//  Ladi
//
//  Created by Michael Latta on 12/2/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

@available(iOS 13.0, *)
struct EventToFileLogger {
  static var queue = DispatchQueue(label: "event_log")
  var path : URL?
  var created : Bool = false
  
  init?() {
    guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    let fileName = "events.log"
    path = documentsDirectory.appendingPathComponent(fileName)
    guard path != nil else { return nil}
    if !FileManager.default.fileExists(atPath: path!.path) {
      self.created = true
      FileManager.default.createFile(atPath: path!.path, contents: nil)
    }
  }
  
  func subscribe(to log: EventLog) -> AnyCancellable {
    return log.receive(on: EventToFileLogger.queue)
      .sink { e in
        do {
          if e.status != .persisted {
            let fileHandle = try? FileHandle(forWritingTo: self.path!)
            var e2 = e
            e2.status = .persisted
            guard fileHandle != nil else {return}
            let data : Data = try e2.encode()
//            if data.count > 400 {
//              NSLog("@@@@ Writing \(String(describing: type(of: e2))) data to file \(data) \(String(data: data.subdata(in: 0..<400), encoding: String.Encoding.utf8)!)...")
//              NSLog(String(data: data.subdata(in: data.count-400..<data.count), encoding: String.Encoding.utf8)!)
//            } else {
//              NSLog("@@@@ Writing \(String(describing: type(of: e2))) data to file \(data) \(String(data: data, encoding: String.Encoding.utf8)!)")
//            }
            fileHandle!.seekToEndOfFile()
            let typeName : String? = TypeTracker.keyFromType(type(of: e2))!
            if typeName == nil || TypeTracker.typeFromKey(typeName!) == nil {
              NSLog("\n\n\n#####\n##### Failed to register type \(typeName ?? "nil")\n#####\n\n\n")
            }
            fileHandle!.write(typeName!.data(using: .utf8)!)
            fileHandle!.write("\n".data(using: .utf8)!)
            fileHandle!.write(data)
            fileHandle!.write("\n".data(using: .utf8)!)
            fileHandle!.closeFile()
          } else {
//            NSLog("@@@@ Skipping writing previously persisted event \(e)")
          }
        } catch {
          // TODO: Handle error so it can be presented in UI to inform user (possibly out of space)
        }
      }
  }
  
  /// load events from the log file if it exists and has content, return true if events were actually loaded
  func loadEvents(store: UndoableEventStore) -> Bool {
    var result = false
    let fileHandle = try? FileHandle(forReadingFrom: self.path!)
    guard fileHandle != nil else {return false}
    fileHandle!.seek(toFileOffset:0)
    let data = fileHandle!.readDataToEndOfFile()
    let str = String(data: data, encoding: .utf8)!
    let events = str.components(separatedBy: "\n")
    for i in stride(from: 0, to: events.count-1, by: 2) {
      let typeName = events[i]
      let json = events[i+1]
      let et : Event.Type = TypeTracker.typeFromKey(typeName) as! Event.Type
      do {
        let event : Event = try et.decode(from: json.data(using: .utf8)!)
        store.append(event)
//        NSLog("@@@@ Loaded event: \(event)")
        result = true
      } catch {
        // TODO: Log error and report to user
        NSLog("#### Error \(error) in loading event \(typeName) \(json)")
      }
    }
    return result
  }
}
