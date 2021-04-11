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

public enum SyncStatus : String {
  case starting
  case creatingZone
  case zoneExists
  case connected
  case offline
  case error
  case manual
}

public enum ICloudSyncMode : String, CaseIterable, Identifiable {
  case manual
  case auto
  
  public var id : String {
    rawValue
  }
}

@available(iOS 14.0, macOS 11.0, *)
public class CloudKitSync : Subscriber {
  public typealias Input = Event
  public typealias Failure = Never

  public static var debugFilter : (_:Event) -> Bool = {e in false}
  
  @Published public var syncMode : ICloudSyncMode = .auto
  @Published public var status : SyncStatus = .manual
  @Published public var readCount : Int = 0
  @Published public var writeCount : Int = 0
  
  public var store : UndoableEventStore?
  
  var sub : Subscription?
  public var fileLogger : EventToFileLogger?
  public var events = Set<UUID>()
  public var userRecordID : CKRecord.ID?
  public var writtenEvents = Set<UUID>()
  
  public var projectRecords = [UUID : CKRecord.ID]()
  public var projectRecordsInProcess = Set<UUID>()
  public var container : CKContainer
  public var privateDB : CKDatabase
  public var sharedDB : CKDatabase
  public var zone : CKRecordZone.ID?
  public var zoneName : String
  private var queue : [UUID:[Event]] = [:]
  
  private var pendingReads : [Event] = []
  
  public var timer = false
  
  private var dispatch = DispatchQueue(label: "com.technomage.icloudSync", qos: .userInitiated, attributes: DispatchQueue.Attributes(), autoreleaseFrequency: .workItem, target: nil)
  
  public init(zoneName : String) {
//    NSLog("\n\n@@@@ Creating IcloudKitSync")
//    print("\n\n@@@@ Creating ICloudKitSync")
    self.zoneName = zoneName
    // default init
    container = CKContainer.default()
    privateDB = container.privateCloudDatabase
    sharedDB = container.sharedCloudDatabase
//    self.writeCancel = self.$writtenCount.receive(on: RunLoop.main).sink { v in
//      print("@@@@ ///////// Writen Count: \(v)")
//    }
//    self.writeCancel = objectWillChange.receive(on: RunLoop.main).sink {
//      print("@@@@ ///////// ICloud sync will change")
//    }
  }
  
  func ensureZoneExists(completion: @escaping () -> Void) {
    let zoneID = CKRecordZone.ID(zoneName: self.zoneName, ownerName: CKCurrentUserDefaultName)
    let op = CKFetchRecordZonesOperation(recordZoneIDs: [zoneID])
    op.queuePriority = .veryHigh
    op.fetchRecordZonesCompletionBlock = { zones, error in
      if zones?.keys.count ?? 0 > 0 {
//        NSLog("@@@@ Received data on \(zones?.count ?? 0) zones \(String(describing: zones?.keys))")
//        print("@@@@ Received data on \(zones?.count ?? 0) zones \(String(describing: zones?.keys))")
        self.zone = zoneID
        self.status = .zoneExists
        completion()
        self.saveQueuedEvents()
      } else {
//        NSLog("@@@@ Custom zone not found, creating it")
        self.status = .creatingZone
        let createZoneGroup = DispatchGroup()
        createZoneGroup.enter()
        let zoneID = CKRecordZone.ID(zoneName: self.zoneName, ownerName: CKCurrentUserDefaultName)
        let customZone = CKRecordZone(zoneID: zoneID)
        let createZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [customZone], recordZoneIDsToDelete: [] )
        createZoneOperation.modifyRecordZonesCompletionBlock = { (saved, deleted, error) in
          if (error == nil) {
//            NSLog("@@@@ Custom zone created \(zoneID)")
//            print("@@@@ Custom zone created \(zoneID)")
            self.zone = zoneID
            self.status = .zoneExists
            completion()
            self.saveQueuedEvents()
          } else {
            // TODO: custom error handling
            print("#### Error in creating custom CloudKit zone \(String(describing: error))")
            ErrTracker.log(Err(msg: "CloudKit not working",
                               details: "Error in creating CloudKit zone: \(String(describing: error))"))
            self.status = .error
          }
          createZoneGroup.leave()
        }
        createZoneOperation.qualityOfService = .userInitiated
        self.privateDB.add(createZoneOperation)
      }
    }
    privateDB.add(op)
  }
  
  /// Load project roots from iCloud
  public func loadProjectRoots(callback: @escaping (_ p:UUID) -> Void) {
    if self.zone == nil {
      dispatch.asyncAfter(deadline: .now() + 1.0) {
        self.loadProjectRoots(callback: callback)
      }
    } else {
      let query = CKQuery(recordType: RecordType.projectRoot.rawValue, predicate: NSPredicate(format: "TRUEPREDICATE"))
      let operation = CKQueryOperation(query: query)
      operation.zoneID = self.zone
      self.fetchRoots(operation, callback: callback)
    }
  }
  
  func fetchRoots(_ op: CKQueryOperation, callback: @escaping (_ p:UUID) -> Void) {
    op.queuePriority = .veryHigh
    op.recordFetchedBlock = { rec in
      let p = UUID(uuidString: rec.recordID.recordName)
//      print("@@@@ Found root for \(p!.uuidString)")
      self.projectRecords[p!] = rec.recordID
      callback(p!)
    }
    op.queryCompletionBlock = { recs, error in
      if error == nil && recs != nil {
//        print("@@@@ Getting next batch of events")
        let op = CKQueryOperation(cursor: recs!)
        self.fetchRoots(op, callback: callback)
      } else if error != nil {
        ErrTracker.log(Err(msg: "Failed to fetch records from CloudKit",
                           details: "Error in fetching CloudKit records: \(String(describing: error))"))
        self.status = .error
        print("#### Error in fetching roots from zone \(String(describing: self.zone)): \(String(describing: error))")
      }
//      NSLog("@@@@ loaded \(self.projectRecords.count) roots")
    }
    self.privateDB.add(op)
  }
  
  /// Load records from iCloud for the provided project
  public func loadRecords(forProject project: UUID, callback: @escaping () -> Void) {
    if self.zone == nil {
      dispatch.asyncAfter(deadline: .now() + 1.0) {
        self.loadRecords(forProject: project, callback: callback)
      }
    } else {
      let query = CKQuery(recordType: RecordType.event.rawValue, predicate: NSPredicate(format: "%@ = \(EventSchema.projectID)", project.uuidString))
      query.sortDescriptors = [sort]
      let operation = CKQueryOperation(query: query)
      operation.zoneID = self.zone
      self.fetchRecords(operation, callback: callback)
    }
  }
  
  /// Load records from iCloud for the provided project's base events that define the project itself
  public func loadProjectRecords(forProject project: UUID, callback: @escaping () -> Void) {
    if self.zone == nil {
      dispatch.asyncAfter(deadline: .now() + 1.0) {
        self.loadRecords(forProject: project, callback: callback)
      }
    } else {
      let query = CKQuery(recordType: RecordType.event.rawValue, predicate: NSPredicate(format: "%@ = \(EventSchema.projectID) AND %@ = \(EventSchema.subjectID)", project.uuidString, project.uuidString))
      query.sortDescriptors = [sort]
      let operation = CKQueryOperation(query: query)
      operation.zoneID = self.zone
      self.fetchRecords(operation, callback: callback)
    }
  }
  
  let sort = NSSortDescriptor(key: "seq", ascending: true)
  
  func fetchRecords(_ op: CKQueryOperation, callback: @escaping () -> Void) {
    op.queuePriority = .veryHigh
    op.recordFetchedBlock = { rec in
      let eventId = UUID(uuidString: rec[EventSchema.eventID] as! String)!
      if !self.events.contains(eventId) && !(self.fileLogger?.savedEvents.contains(eventId) ?? false) {
//        NSLog("@@@@ ---- Cloud loading event \(self.events.count)")
//        print("@@@@ -÷--- Cloud loading event \(self.events.count) \(eventId) \(rec[EventSchema.seq] as! String) known events: \(self.events)")
        self.events.insert(eventId)
        // deserialize event from icloud and add to store if not previously seen by it
        let typeName = rec[EventSchema.eventType] as! String
        var data : Data?
        if let d = rec[EventSchema.eventData] {
          data = (d as! Data)
        } else {
          let asset : CKAsset = rec[EventSchema.eventAsset] as! CKAsset
          do {
            data = try Data(contentsOf: asset.fileURL!)
          } catch {
            print("#### Error \(error) in loading event \(typeName)")
            ErrTracker.log(Err(msg: "Failed to load data from iCloud",
                               details: "Error in loading \(typeName) event: \(String(describing: error))"))
            self.status = .error
          }
        }
        let et : Event.Type = TypeTracker.typeFromKey(typeName) as! Event.Type
        do {
//          print("@@@@ \(typeName) event data \(String(data: data!, encoding: .utf8) ?? "<none>")")
          let event : Event = try et.decode(from: data!)
          if event.id != eventId {
            print("########## Event read from icloud without proper id #############")
            ErrTracker.log(Err(msg: "ICloud Coding Error",
                               details: "ICloud event without proper ID"))
          }
          self.pendingReads.append(event)
        } catch {
          let json : String = String(data: data!, encoding: .utf8)!
          print("#### Error \(error) in loading event \(typeName) \(json)")
          ErrTracker.log(Err(msg: "Error loading data from iCloud",
                             details: "Error loading event \(typeName): \(error)"))
          self.status = .error
        }
      }
    }
    op.queryCompletionBlock = { recs, error in
      if error == nil && recs != nil {
        let op = CKQueryOperation(cursor: recs!)
        self.fetchRecords(op, callback: callback)
      } else if error != nil {
        print("#### Error in fetching records from zone \(String(describing: self.zone)): \(String(describing: error))")
        ErrTracker.log(Err(msg: "Error in fetching data from iCloud",
                           details: "Error in fetching CloudKit records from zone: \(String(describing: self.zone)): \(String(describing: error))"))
        self.status = .error
      } else {
        let sorted = self.pendingReads.sorted { (a,b) -> Bool in
          return a.seq!.sortableString < b.seq!.sortableString
        }
//        print("@@@@ Loaded \(sorted.count) iCloud events")
        self.pendingReads = []
        self.readCount += sorted.count
        for e in sorted {
          if CloudKitSync.debugFilter(e) {
            print("@@@@ Debug Event \(e.seq!.sortableString): \(String(describing: e))")
          }
          DispatchQueue.main.async {
            self.store?.append(e)
          }
        }
        callback()
      }
    }
    self.privateDB.add(op)
  }

  /// Connect to cloudkit
  public func connect() {
    status = .starting
    let container = CKContainer.default()
    
    container.requestApplicationPermission(.userDiscoverability) { (status, error) in
      guard error == nil else {
        print("#### Failed to get user discovery permission \(String(describing: error))")
        ErrTracker.log(Err(msg: "User Discovery permission not found",
                           details: "Failed to get user discovery permission: \(String(describing: error))"))
        self.status = .error
        return
      }
      container.accountStatus { accountStatus, error in
        guard error == nil else {
          print("#### Failed to get account status \(String(describing: error))")
          ErrTracker.log(Err(msg: "Failed to get iCloud account status",
                             details: "Failed to get account status: \(String(describing: error))"))
          self.status = .error
          return
        }
        if accountStatus == .available {
          container.fetchUserRecordID { (recordID, error) in
            guard let userRecordID = recordID else {
//              print("@@@@ No user ID available")
              ErrTracker.log(Err(msg: "Unable to get user ID for iCloud",
                                 details: "No user ID available: \(String(describing: error))"))
              self.status = .offline
              return
            }
            container.discoverUserIdentity(withUserRecordID: userRecordID) { (userID, error) in
              if error != nil {
                print("#### Error in getting user info \(String(describing: error))")
                ErrTracker.log(Err(msg: "Error in getting user info from iCloud",
                                   details: "Error in getting user info: \(String(describing: error))"))
                self.status = .error
              } else if userID != nil {
                print("User record ID: \(userRecordID)")
                print("User has account: \(userID!.hasiCloudAccount)")
                let nam = userID!.nameComponents!
                print("User name: \(nam.givenName ?? "") \(nam.familyName ?? "")")
                print("Contacts: \(userID!.contactIdentifiers)")
              }
              self.ensureZoneExists {
                if self.status != .error {
                  self.status = .connected
                }
                self.loadProjectRoots() { p in
                  // Load project defining events
                  self.loadProjectRecords(forProject: p) {
                  }
                }
                self.userRecordID = userRecordID
                NSLog("User record id \(userRecordID)")
              }
            }
          }
        } else {
          self.status = .offline
        }
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
//      print("\n\n@@@@ Received event \(input.id) \(input.status.rawValue) after testing for previous event and status")
      self.events.insert(input.id)
      self.appendToQueue(input)
    }
    return Subscribers.Demand.unlimited
  }
  
  func startTimer() {
    if !timer {
//      print("@@@@ Starting timer")
      timer = true
      dispatch.asyncAfter(deadline: .now() + 5.0) {
//        print("@@@@ Timer completed, saving queued events")
        self.timer = false
        self.saveQueuedEvents()
      }
    }
  }
  
  /// Save events queued while zone was being created
  func saveQueuedEvents() {
    self.dispatch.async {
//      print("@@@@ Saving queued events \(self.queue.count)")
      // Process queued events from this app
      if self.queue.count > 0 {
        // Save queued events to database
        perfStart("Save batch to iCloud with \(self.queue.count) events")
//        NSLog("@@@@ Processing \(self.queue.count) queued events")
        let recs = self.queue
        self.queue = [:]
        do {
          for id in recs.keys {
            if let root = self.projectRecords[id] {
              try self.save(rootRecordID: root, events: recs[id]!)
            } else {
//              print("@@@@ Requeing events waiting for root \(id)")
              for e in recs[id]! {
                self.appendToQueue(e)
              }
            }
          }
        } catch {
          print("#### Error in saving queued events \(String(describing: error))")
          // Error handling
          ErrTracker.log(Err(msg: "Error in saving data to iCloud",
                             details: "Error in saving queued CloudKit events: \(String(describing: error))"))
          self.status = .error
        }
        perfEnd("Save batch to iCloud")
      }
    }
  }
  
  /// Add an event to the queue to be written to iCloud when the timer next goes off
  func appendToQueue(_ input: Event) {
    self.dispatch.async {
      let project = input.project
      if let zone = self.zone {
        self.ensureProjectRoot(project: project, zone: zone)
      }
      var list = self.queue[project] ?? []
      list.append(input)
      self.queue[project] = list
      self.startTimer()
    }
  }
  
  /// Process an event given zone exists
  func processEvent(_ input : Event) throws {
    guard self.zone != nil else {
      self.appendToQueue(input)
      return
    }
    guard !projectRecordsInProcess.contains(input.project) else {
      self.appendToQueue(input)
      return
    }
    // Write event to cloudkit
    if !projectRecords.keys.contains(input.project) {
      self.appendToQueue(input)
    } else {
      // Get the project root
//      NSLog("@@@@ Using existing projet root for \(input.project)")
//      print("@@@@ Using existing projet root for \(input.project)")
      let projectRoot = projectRecords[input.project]!
      try save(rootRecordID: projectRoot, event: input)
    }
  }
  
  /// Ensure a project root exists for a project
  func ensureProjectRoot(project : UUID, zone : CKRecordZone.ID) {
    guard !projectRecordsInProcess.contains(project) else {
      return
    }
//    print("@@@@ Ensuring project root exists for \(project)")
    if !projectRecords.keys.contains(project) {
//      NSLog("@@@@ Creating project root for \(project)")
//      print("@@@@ Creating project root for \(project)")
      projectRecordsInProcess.insert(project)
      // Create the project root record
      let projectType : String = RecordType.projectRoot.rawValue
      let op = CKModifyRecordsOperation()
      op.queuePriority = .veryHigh
      let rec = CKRecord(recordType: projectType, recordID: CKRecord.ID(recordName: project.uuidString, zoneID: zone))
      op.recordsToSave = [rec]
      op.modifyRecordsCompletionBlock = { roots, _, error in
        guard error == nil else {
          print("#### Error in saving project root to icloud \(project): \(String(describing: error))")
          ErrTracker.log(Err(msg: "Unable to save project to iCloud",
                             details: "\(String(describing: error))"))
          self.status = .error
          return
        }
//        print("@@@@ Project root created for \(project)")
        let root = roots![0]
        // Update on main queue to ensure sequential processing
        self.projectRecords[project] = root.recordID
        self.projectRecordsInProcess.remove(project)
        self.saveQueuedEvents()
      }
      privateDB.add(op)
    }
  }
  
  /// Save records with project record as root
  func save(rootRecordID root: CKRecord.ID, events: [Event]) throws {
//    print("\n\n@@@@ Saving event \(event.id) \(self.writtenCount) to iCloud")
    var recs = [CKRecord]()
    var evts = [Event]()
    for event in events {
      var evt = event
      evt.status = .persisted
      let eventType : String = RecordType.event.rawValue
      let rec = CKRecord(recordType: eventType, recordID: CKRecord.ID(__recordName: evt.id.uuidString, zoneID: zone!))
      rec.setParent( root )
      try saveEventToRecord(rec: rec, evt: evt)
      recs.append(rec)
      evts.append(event)
      if recs.count > 200 && recs.count < events.count {
        saveBatch(recs: recs, events: evts)
        recs = []
        evts = []
      }
    }
    saveBatch(recs: recs, events: evts)
  }
  
  func saveEventToRecord(rec: CKRecord, evt: Event) throws {
    let data = try evt.encode()
//    print("\n\n\n@@@ Writing data \(data.count) bytes")
    if data.count < 900_000 {
      rec[EventSchema.eventData] = data
    } else {
//      print("@@@@ Saving as asset field\n\n")
      let url = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString+".dat")
      do {
        try data.write(to: url!, options: [])
      } catch {
        NSLog("#### Error! \(error)");
        ErrTracker.log(Err(msg: "Error in saving large event to iCloud (probably an attachment)",
                           details: "\(error)"))
        return
      }
      rec[EventSchema.eventAsset] = CKAsset(fileURL: url!)
    }
    rec[EventSchema.eventType] = TypeTracker.keyFromType(type(of: evt))!
    rec[EventSchema.seq] = evt.seq!.sortableString
    rec[EventSchema.eventID] = evt.id.uuidString
    rec[EventSchema.projectID] = evt.project.uuidString
    rec[EventSchema.subjectID] = evt.subject.uuidString
  }
  
  func saveBatch( recs: [CKRecord], events: [Event]) {
//    NSLog("@@@@ Saving batch of \(recs.count) records")
    let op = CKModifyRecordsOperation()
    op.queuePriority = .veryHigh
    op.recordsToSave = recs
    op.modifyRecordsCompletionBlock = { _, _, error in
      guard error == nil else {
        print("#### Error in saving event \(String(describing: error))")
        ErrTracker.log(Err(msg: "Error in saving data to iCloud",
                           details: "\(String(describing: error))"))
        self.status = .error
        return}
      perfMsg("Saved \(events.count) events")
      if events.count > 0 {
        for e in events {
          self.writtenEvents.insert(e.id) // TODO: occasional crash, probably threading
        }
        if self.writeCount != self.writtenEvents.count {
          self.writeCount = self.writtenEvents.count
        }
      }
    }
    privateDB.add(op)
  }
  
  /// Save a record with project record as root
  func save(rootRecordID root: CKRecord.ID, event: Event) throws {
    //    print("\n\n@@@@ Saving event \(event.id) \(self.writtenCount) to iCloud")
    var evt = event
    evt.status = .persisted
    let eventType : String = RecordType.event.rawValue
    let rec = CKRecord(recordType: eventType, recordID: CKRecord.ID(__recordName: evt.id.uuidString, zoneID: zone!))
    rec.setParent( root )
    try saveEventToRecord(rec: rec, evt: evt)
    let op = CKModifyRecordsOperation()
    op.queuePriority = .veryHigh
    op.recordsToSave = [rec]
    op.modifyRecordsCompletionBlock = { _, _, error in
      guard error == nil else {
        print("#### Error in saving event \(String(describing: error))")
        ErrTracker.log(Err(msg: "Error in saving data to iCloud",
                           details: "\(String(describing: error))"))
        self.status = .error
        return}
      self.writtenEvents.insert(event.id)
      if self.writeCount != self.writtenEvents.count {
        self.writeCount = self.writtenEvents.count
      }
    }
    privateDB.add(op)
  }
  
  /// Cancel the subscription
  public func receive(completion: Subscribers.Completion<Never>) {
    sub?.cancel()
    sub = nil
  }
  
  /// Perform a manual sync
  public func syncNow() {
    
  }
}
