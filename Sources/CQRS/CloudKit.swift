//
//  CloudKitRecordTypes.swift
//  CQRS
//
//  Created by Michael Latta on 4/23/20.
//  Copyright © 2020 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation

public enum RecordType : String, Codable {
  case projectRoot
  case event
}

public struct EventSchema {
  public static let eventData = "event"
  public static let eventAsset = "asset"
  public static let eventType = "eventType"
  public static let seq = "seq"
  public static let eventID = "eventID"
  public static let projectID = "projectID"
  public static let subjectID = "subjectID"
}

public struct ProjectRootSchema {
  public static let name = "name"
}
