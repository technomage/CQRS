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
}

@available(iOS 13.0, macOS 10.15, *)
public class CloudKitSync : Subscriber, Identifiable, Aggregator, ObservableObject {
  public typealias Input = Event
  public typealias Failure = Never

  public var id = UUID()
  @Published public var status : SyncStatus = .starting
  var sub : Subscription?
  public var store : UndoableEventStore?
  public var fileLogger : EventToFileLogger?
  public var events : Set<UUID> = []
  public var userRecordID : CKRecord.ID?
  public var writtenEvents : [UUID] = []
  
  public var projectRecords = [UUID : CKRecord.ID]()
  public var projectRecordsInProcess : [UUID] = []
  public var container : CKContainer
  public var privateDB : CKDatabase
  public var sharedDB : CKDatabase
  public var zone : CKRecordZone.ID?
  public var zoneName : String
  private var queue : [Event] = []
  
  private var pendingReads : [Event] = []
  
  @Published public var loadedCount : Int = 0
  @Published public var writtenCount : Int = 0
  
  public var writeCancel : AnyCancellable?
  
  public init(zoneName : String) {
    NSLog("\n\n@@@@ Creating IcloudKitSync")
    print("\n\n@@@@ Creating ICloudKitSync")
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
    op.queuePriority = Operation.QueuePriority.high
    op.fetchRecordZonesCompletionBlock = { zones, error in
      if zones?.keys.count ?? 0 > 0 {
        NSLog("@@@@ Received data on \(zones?.count ?? 0) zones \(String(describing: zones?.keys))")
        print("@@@@ Received data on \(zones?.count ?? 0) zones \(String(describing: zones?.keys))")
        self.zone = zoneID
        self.status = .zoneExists
        completion()
        self.saveQueuedEvents()
      } else {
        NSLog("@@@@ Custom zone not found, creating it")
        self.status = .creatingZone
        let createZoneGroup = DispatchGroup()
        createZoneGroup.enter()
        let zoneID = CKRecordZone.ID(zoneName: self.zoneName, ownerName: CKCurrentUserDefaultName)
        let customZone = CKRecordZone(zoneID: zoneID)
        let createZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [customZone], recordZoneIDsToDelete: [] )
        createZoneOperation.modifyRecordZonesCompletionBlock = { (saved, deleted, error) in
          if (error == nil) {
            NSLog("@@@@ Custom zone created \(zoneID)")
            print("@@@@ Custom zone created \(zoneID)")
            self.zone = zoneID
            self.status = .zoneExists
            completion()
            self.saveQueuedEvents()
          } else {
            // TODO: custom error handling
            NSLog("#### Error in creating custom CloudKit zone \(String(describing: error))")
            print("#### Error in creating custom CloudKit zone \(String(describing: error))")
            DispatchQueue.main.async {
              self.status = .error
            }
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
          self.status = .error
        }
      }
    }
  }
  
  /// Load project roots from iCloud
  public func loadProjectRoots(callback: @escaping (_ p:UUID) -> Void) {
    if self.zone == nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
    op.queuePriority = .high
    op.recordFetchedBlock = { rec in
      let p = UUID(uuidString: rec.recordID.recordName)
      NSLog("@@@@ Found root for \(p!.uuidString)")
      self.projectRecords[p!] = rec.recordID
      callback(p!)
    }
    op.queryCompletionBlock = { recs, error in
      if error == nil && recs != nil {
        NSLog("@@@@ Getting next batch of events")
        let op = CKQueryOperation(cursor: recs!)
        self.fetchRoots(op, callback: callback)
      } else if error != nil {
        DispatchQueue.main.async {
          self.status = .error
        }
        NSLog("#### Error in fetching roots from zone \(String(describing: self.zone)): \(String(describing: error))")
      }
      NSLog("@@@@ loaded \(self.projectRecords.count) roots")
    }
    self.privateDB.add(op)
  }
  
  /// Load records from iCloud for the provided project
  public func loadRecords(forProject project: UUID, callback: @escaping () -> Void) {
    if self.zone == nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
    op.queuePriority = .high
    op.recordFetchedBlock = { rec in
      let eventId = UUID(uuidString: rec[EventSchema.eventID] as! String)!
      if !self.events.contains(eventId) && !(self.fileLogger?.savedEvents.contains(eventId) ?? false) {
//        NSLog("@@@@ ---- Cloud loading event \(self.events.count)")
//        print("@@@@ ---- Cloud loading event \(self.events.count) \(eventId) \(rec[EventSchema.seq] as! String) known events: \(self.events)")
        self.events.insert(eventId)
        // deserialize event from icloud and add to store if not previously seen by it
        let typeName = rec[EventSchema.eventType] as! String
        let data = rec[EventSchema.eventData] as! Data
        let et : Event.Type = TypeTracker.typeFromKey(typeName) as! Event.Type
        do {
          let event : Event = try et.decode(from: data)
          if event.id != eventId {
            print("########## Event read from icloud without proper id #############")
          }
          self.pendingReads.append(event)
        } catch {
          let json : String = String(data: data, encoding: .utf8)!
          NSLog("#### Error \(error) in loading event \(typeName) \(json)")
          self.status = .error
        }
      }
    }
    op.queryCompletionBlock = { recs, error in
//      print("@@@@ completed a query to fetch events")
      if error == nil && recs != nil {
//        NSLog("@@@@ Getting next batch of events")
        let op = CKQueryOperation(cursor: recs!)
        self.fetchRecords(op, callback: callback)
      } else if error != nil {
        NSLog("#### Error in fetching records from zone \(String(describing: self.zone)): \(String(describing: error))")
        self.status = .error
      } else {
//        print("@@@@ calling callback on fetchRecords")
        let sorted = self.pendingReads.sorted { (a,b) -> Bool in
          return a.seq!.sortableString < b.seq!.sortableString
        }
        self.pendingReads = []
        DispatchQueue.main.async {
          for e in sorted {
//            print("@@@@ ==== Processing sorted event \(e.id.uuidString) \(e.seq!.sortableString)")
            self.store?.append(e)
          }
//          print("@@@@ |||| Updating loaded count by \(sorted.count)")
          self.loadedCount += sorted.count
          callback()
        }
      }
    }
//    print("@@@@ Starting a new query to fetch events")
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
    
    container.requestApplicationPermission(.userDiscoverability) { (status, error) in
      guard error == nil else {
        NSLog("#### Failed to get user discovery permission \(String(describing: error))")
        DispatchQueue.main.async {
          self.status = .error
        }
        return }
      container.accountStatus { accountStatus, error in
        guard error == nil else {
          NSLog("#### Failed to get account status \(String(describing: error))")
          DispatchQueue.main.async {
            self.status = .error
          }
          return }
        if accountStatus == .available {
          container.fetchUserRecordID { (recordID, error) in
            guard let userRecordID = recordID else {
              NSLog("@@@@ No user ID available")
              self.status = .offline
              return }
            container.discoverUserIdentity(withUserRecordID: userRecordID) { (userID, error) in
              if error != nil {
                print("Error in getting user info \(String(describing: error))")
                self.status = .error
              } else if userID != nil {
                print("User record ID: \(userRecordID)")
                print("User has account: \(userID!.hasiCloudAccount)")
                let nam = userID!.nameComponents!
                print("User name: \(nam.givenName ?? "") \(nam.familyName ?? "")")
                print("Contacts: \(userID!.contactIdentifiers)")
              }
              self.ensureZoneExists {
                self.loadProjectRoots() { p in
                  // Load project defining events
                  self.loadProjectRecords(forProject: p) {}
                }
//                DispatchQueue.main.async {
                  self.userRecordID = userRecordID
                  Seq.localID = userRecordID
                  NSLog("User record id \(userRecordID)")
//                }
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
    guard !projectRecordsInProcess.contains(input.project) else {
      self.queue.append(input)
      return
    }
    // Write event to cloudkit
//    print("@@@@@ Project records keys \(projectRecords.keys)")
    if !projectRecords.keys.contains(input.project) {
      projectRecordsInProcess.append(input.project)
//      NSLog("@@@@ Creating project root for \(input.project) event \(input.id)")
//      print("@@@@ Creating project root for \(input.project) event \(input.id)")
      // Create the project root record
      let projectType : String = RecordType.projectRoot.rawValue
      let op = CKModifyRecordsOperation()
      op.queuePriority = .high
      let rec = CKRecord(recordType: projectType, recordID: CKRecord.ID(recordName: input.project.uuidString, zoneID: zone))
      op.recordsToSave = [rec]
      op.modifyRecordsCompletionBlock = { roots, _, error in
        guard error == nil else {
          NSLog("#### Error in saving project root to icloud \(input.project) event \(input.id): \(String(describing: error))")
          print("#### Error in saving project root to icloud \(input.project) event \(input.id): \(String(describing: error))")
          DispatchQueue.main.async {
            self.status = .error
          }
          return
        }
        let root = roots![0]
//        NSLog("@@@@ Created project root for \(input.project) event \(input.id) : \(String(describing: root?.recordID))")
//        print("@@@@ Created project root for \(input.project) event \(input.id) : \(String(describing: root?.recordID))")
//        DispatchQueue.main.async {
          // Update on main queue to ensure sequential processing
          self.projectRecords[input.project] = root.recordID
          self.projectRecordsInProcess.remove(at: self.projectRecordsInProcess.firstIndex(of: input.project)!)
          self.saveQueuedEvents()
//        }
        do {
          try self.saveEvent(rootRecordID: root.recordID, event: input)
        } catch {
          // Error handling
          NSLog("#### Error in saving event to icloud \(input.project)")
          print("#### Error in saving event to icloud \(input.project)")
          self.status = .error
        }
        
      }
      privateDB.add(op)
    } else {
      // Get the project root
//      NSLog("@@@@ Using existing projet root for \(input.project)")
//      print("@@@@ Using existing projet root for \(input.project)")
      let projectRoot = projectRecords[input.project]!
      try saveEvent(rootRecordID: projectRoot, event: input)
    }
  }
  
  /// Save a record with project record as root
  func saveEvent(rootRecordID root: CKRecord.ID, event: Event) throws {
//    print("\n\n@@@@ Saving event \(event.id) \(self.writtenCount) to iCloud")
    var evt = event
    evt.status = .persisted
    let eventType : String = RecordType.event.rawValue
    let rec = CKRecord(recordType: eventType, recordID: CKRecord.ID(__recordName: evt.id.uuidString, zoneID: zone!))
    rec.setParent( root )
    rec[EventSchema.eventData] = try evt.encode()
    rec[EventSchema.eventType] = TypeTracker.keyFromType(type(of: evt))!
    rec[EventSchema.seq] = evt.seq!.sortableString
    rec[EventSchema.eventID] = evt.id.uuidString
    rec[EventSchema.projectID] = evt.project.uuidString
    rec[EventSchema.subjectID] = evt.subject.uuidString
    let op = CKModifyRecordsOperation()
    op.queuePriority = .high
    op.recordsToSave = [rec]
    op.modifyRecordsCompletionBlock = { _, _, error in
      guard error == nil else {
        NSLog("#### Error in saving event \(String(describing: error))")
        self.status = .error
        return}
      DispatchQueue.main.async {
        self.updateWriteCount(event: event)
      }
    }
    privateDB.add(op)
  }
  
  public func updateWriteCount(event: Event) {
    self.writtenEvents.append(event.id)
    self.writtenCount = self.writtenEvents.count
//    print("@@@@ Event \(event.id) \(self.writtenCount) saved")
  }
  
  /// Cancel the subscription
  public func receive(completion: Subscribers.Completion<Never>) {
    sub?.cancel()
    sub = nil
  }
}
