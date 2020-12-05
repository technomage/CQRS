//
//  CQRS.swift
//  CQRS
//
//  Created by Michael Latta on 2/17/20.
//  Copyright © 2020 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import CloudKit

@available(iOS 14.0, macOS 11.0, *)
public class Utils {
  public static func resetFiles() {
    print("\n\n@@@@ Resetting Files\n\n")
    if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      let paths = FileManager.default.enumerator(atPath: documentsDirectory.path)
      if paths != nil {
        for p in paths! {
          let path = p as! String
          let fullPath = documentsDirectory.appendingPathComponent(path)
          try? FileManager.default.removeItem(at: fullPath)
        }
      }
    }
  }
  
  public static func resetICloud(zoneName : String, callback: @escaping ([CKRecordZone]?, [CKRecordZone.ID]?, Error?) -> Void) {
    print("\n\n@@@@ Resetting iCloud\n\n")
    let container = CKContainer.default()
    let privateDB = container.privateCloudDatabase
    let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    let op = CKModifyRecordZonesOperation()
    op.queuePriority = .high
    op.recordZoneIDsToDelete = [zoneID]
    op.modifyRecordZonesCompletionBlock = callback
    privateDB.add(op)
  }
}
