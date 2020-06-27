//
//  CloudKitSync.swift
//  CQRS
//
//  Created by Michael Latta on 4/20/20.
//  Copyright © 2020 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine
import CloudKit

@available(iOS 13.0, macOS 10.15, *)
public class CloudKitSync : Subscriber, Identifiable, Aggregator, ObservableObject {
  public typealias Input = Event
  public typealias Failure = Never

  public var id = UUID()
  var sub : Subscription?
  public var store : UndoableEventStore?
  public var fileLogger : EventToFileLogger?
  @Published public var events : [UUID] = []
  @Published public var userRecordID : CKRecord.ID?
  
  public var projectRecords = [UUID:CKRecord.ID]()
  public var container : CKContainer
  public var privateDB : CKDatabase
  public var sharedDB : CKDatabase
  public var zone : CKRecordZone.ID?
  public var root : CKRecord.ID?
  public var zoneName : String
  private var queue : [Event] = []
  
  @Published public var loadedCount = 0
  
  public init(zoneName : String) {
    self.zoneName = zoneName
    // default init
    container = CKContainer.default()
    privateDB = container.privateCloudDatabase
    sharedDB = container.sharedCloudDatabase
    let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    let op = CKFetchRecordZonesOperation(recordZoneIDs: [zoneID])
    op.queuePriority = Operation.QueuePriority.high
    op.fetchRecordZonesCompletionBlock = { zones, error in
      if zones?.keys.count ?? 0 > 0 {
        NSLog("@@@@ Received data on \(zones?.count ?? 0) zones \(zones?.keys)")
        self.zone = zoneID
        self.saveQueuedEvents()
      } else {
        NSLog("@@@@ Custom zone not found, creating it")
        let createZoneGroup = DispatchGroup()
        createZoneGroup.enter()
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let customZone = CKRecordZone(zoneID: zoneID)
        let createZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [customZone], recordZoneIDsToDelete: [] )
        createZoneOperation.modifyRecordZonesCompletionBlock = { (saved, deleted, error) in
          if (error == nil) {
            NSLog("@@@@ Custom zone created \(zoneID)")
            self.zone = zoneID
            self.saveQueuedEvents()
          } else {
            // custom error handling
          }
          createZoneGroup.leave()
        }
        createZoneOperation.qualityOfService = .userInitiated
        self.privateDB.add(createZoneOperation)
      }
    }
    privateDB.add(op)
  }
  
  /// Save events queued while zone was being created
  func saveQueuedEvents() {
    // Process queued events from this app
    if self.queue.count > 0 {
      // Save queued events to database
      NSLog("@@@@ Processing \(self.queue.count) queued events")
      let recs = self.queue
      self.queue = []
      for e in recs {
        do {
          try self.processEvent(e)
        } catch {
          // Error handling
        }
      }
    }
  }
  
  /// Load records from iCloud for the provided project
  public func loadRecords(forProject project: UUID, callback: @escaping () -> Void) {
    if self.zone == nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self.loadRecords(forProject: project, callback: callback)
      }
    } else {
      let query = CKQuery(recordType: RecordType.event.rawValue, predicate: NSPredicate(format: "%@ = \(RecordSchema.projectID)", project.uuidString))
      let operation = CKQueryOperation(query: query)
      operation.zoneID = self.zone
      self.fetchRecords(operation, callback: callback)
    }
  }
  
  func fetchRecords(_ op: CKQueryOperation, callback: @escaping () -> Void) {
    op.queuePriority = Operation.QueuePriority.high
    op.recordFetchedBlock = { rec in
      let eventId = UUID(uuidString: rec[RecordSchema.eventID] as! String)!
      if !self.events.contains(eventId) && !(self.fileLogger?.savedEvents.contains(eventId) ?? false) {
        NSLog("@@@@ ---- Cloud loading event \(self.events.count)")
        self.events.append(eventId)
//        DispatchQueue.main.async {
//          self.loadedCount += 1
//          NSLog("@@@@ Got event \(self.loadedCount) from cloud kit zone: \(rec)")
//          // TODO: Merge icloud events with file loaded events where appropriate,
//          // possibly update fetch to just get changes since last sync
//        }
      }
    }
    op.queryCompletionBlock = { recs, error in
      if error == nil && recs != nil {
        NSLog("@@@@ Getting next batch of events")
        let op = CKQueryOperation(cursor: recs!)
        self.fetchRecords(op, callback: callback)
      }else if error != nil {
        NSLog("#### Error in fetching records from zone \(self.zone): \(error)")
      } else {
        DispatchQueue.main.async {
          self.loadedCount = self.events.count
        }
        callback()
      }
    }
    self.privateDB.add(op)
  }
  
  public convenience init(zoneName: String, store: UndoableEventStore?) {
    self.init(zoneName: zoneName)
    self.store = store
    guard store != nil else {return}
    store!.log.subscribe(self)
  }
  
  /// Connect to cloudkit
  public func connect() {
    let container = CKContainer.default()
    container.accountStatus { accountStatus, error in
      if accountStatus == .available {
        container.fetchUserRecordID { recordID, error in
          guard let userRecordID = recordID else {
            NSLog("@@@@ No user ID available")
            return }
          guard error == nil else {
            NSLog("@@@@ Error in getting user ID \(error)")
            return }
          DispatchQueue.main.async {
            self.userRecordID = userRecordID
            Seq.localID = userRecordID
            NSLog("User record id \(userRecordID)")
          }
        }
      } else {
        NSLog("@@@@ Cloudkit not logged in")
      }
    }
  }
  
  public func receive(subscription: Subscription) {
    sub = subscription
    subscription.request(Subscribers.Demand.unlimited)
  }
  
  /// Subscribe to the store to receive events
  public func subscribeToStore() {
    guard self.fileLogger != nil else {return}
    self.fileLogger!.subscribe(self)
  }
  
  /// Test if an event should be saved
  public func test(_ input : Event) -> Bool {
    return !self.events.contains(input.id) && input.status != .cached && input.status != .persisted
  }
  
  /// Receive an event to be saved to cloud kit
  public func receive(_ input: Event) -> Subscribers.Demand {
    if self.test(input) {
      self.events.append(input.id)
      DispatchQueue.main.async {
        self.loadedCount += 1
      }
      if self.zone != nil {
        do {
          try processEvent(input)
        } catch {
          self.queue.append(input)
        }
      } else {
        queue.append(input)
      }
    }
    return Subscribers.Demand.unlimited
  }
  
  /// Process an event given zone exists
  func processEvent(_ input : Event) throws {
    guard let zone = self.zone else {return}
    // Write event to cloudkit
    if !projectRecords.keys.contains(input.project) {
      // Create the project root record
      let projectType : String = RecordType.projectRoot.rawValue
      let rec = CKRecord(recordType: projectType, recordID: CKRecord.ID(zoneID: zone))
      privateDB.save(rec) { root, error in
        guard error == nil else {return}
        self.projectRecords[input.project] = root!.recordID
        do {
          try self.saveEvent(rootRecordID: root!.recordID, event: input)
        } catch {
          // Error handling
        }
        
      }
    } else {
      // Get the project root
      let projectRoot = projectRecords[input.project]!
      try saveEvent(rootRecordID: projectRoot, event: input)
    }
  }
  
  /// Save a record with project record as root
  func saveEvent(rootRecordID root: CKRecord.ID, event: Event) throws {
    var evt = event
    evt.status = .persisted
    let eventType : String = RecordType.event.rawValue
    let rec = CKRecord(recordType: eventType, recordID: CKRecord.ID(__recordName: evt.id.uuidString, zoneID: zone!))
    rec.setParent( self.root )
    rec[RecordSchema.eventData] = try evt.encode()
    rec[RecordSchema.eventType] = TypeTracker.keyFromType(type(of: evt))!
    rec[RecordSchema.seq] = evt.seq!.sortableString
    rec[RecordSchema.eventID] = evt.id.uuidString
    rec[RecordSchema.projectID] = evt.project.uuidString
    privateDB.save(rec) { rec, error in
      NSLog("@@@@ event record saved")
      DispatchQueue.main.async {
        self.loadedCount = self.events.count
      }
    }
  }
  
  /// Cancel the subscription
  public func receive(completion: Subscribers.Completion<Never>) {
    sub?.cancel()
    sub = nil
  }
}
