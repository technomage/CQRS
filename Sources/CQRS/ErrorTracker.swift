//
//  ErrorTracker.swift
//  
//  Track errors encountered in the system.
//  Each error can be user visible or at the
//  programmer level.  User visible errors are
//  things that end-users can do something about,
//  programmer errors are meant for programmers.
//  End users are prompted to send error reports
//  to the programmer when errors are encountered.
//
//  Created by Michael Latta on 12/4/20.
//

import Foundation
import Combine

@available(iOS 14.0, *)
public class ErrTracker : ObservableObject {
  @Published public var errors = [Err]()
  public var docDirectory : URL?
  public var path : URL?

  public static func log(_ err : Err) {
    ErrTracker.current.log(err)
  }
      
  public func log(_ err: Err) {
    do {
      let fileHandle = try? FileHandle(forWritingTo: self.path!)
      guard fileHandle != nil else {return}
      fileHandle?.seekToEndOfFile()
      let enc = JSONEncoder()
      let data = try enc.encode(err)
      fileHandle!.write(data)
    } catch {
      NSLog("#### Failed to save exception: \(err)")
    }
    DispatchQueue.main.async {
      ErrTracker.current.errors.append(err)
    }
  }
  
  public init?() {
    guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    docDirectory = documentsDirectory
    let fileName = "errs.log"
    path = documentsDirectory.appendingPathComponent(fileName)
    guard path != nil else { return nil}
    if FileManager.default.fileExists(atPath: path!.path) {
      let fileHandle = try? FileHandle(forReadingFrom: path!)
      fileHandle!.seek(toFileOffset:0)
      let data = fileHandle!.readDataToEndOfFile()
      let str = String(data: data, encoding: .utf8)!
      let errs = str.components(separatedBy: "\n")
      FileManager.default.createFile(atPath: path!.path, contents: nil)
      for d2 in errs {
        do {
          let dec = JSONDecoder()
          let err = try dec.decode(Err.self, from: d2.data(using: .utf8)!)
          log(err)
        } catch {
          NSLog("#### Failed to recover errors from prior run")
        }
      }
    } else {
      FileManager.default.createFile(atPath: path!.path, contents: nil)
    }
  }
  
  public static var current : ErrTracker = ErrTracker()!
}

public struct Err : Identifiable,Codable {
  public var id = UUID()
  public var date = Date()
  public var msg: String
  public var details : String
  
  public init(msg: String, details: String) {
    self.msg = msg
    self.details = details
  }
}
