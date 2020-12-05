//
//  Seq.swift
//  CQRS
//
//  Created by Michael Latta on 4/19/20.
//  Copyright © 2020 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import CloudKit

/// This class provides the sequence for psudo-ordering of all events.
/// Each user of the system generates events sequened using this class,
/// As they encounter other users (sharing of projects) the sequence
/// for events includes the time from those other users eo allow convergence
/// of changes over time.  For example if user A creates a project and adds
/// 3 entries, and then shares this with user B then when B adds a 4th entry
/// its sequence will include knowledge that it followed user A's 3rd entry
/// in sequence.  If A in the mean time creates 2 more entries then their
/// sequence will include that they happened after A's 3 entry and before
/// any entries by B.  When these are merged the system can detect the
/// ordering of events and do a proper merge of the changes. Inserts are
/// relatively easy, but when deletes and updates are mixed in it becomes
/// more "interesting" and is generally called a CRDT system.  This class
/// just provides the sequencing that allows the merge.  Merges occurr in
/// aggregators, and sharing of data in event stores.

@available(iOS 14.0, macOS 11.0, *)
public struct Seq : Equatable, Codable {
  public static var localID : UUID? = nil
  /// The time values for each known user
  public var counts : [UUID : UInt]
  
  /// Initialize a Seq at base values, use next() to increment the
  /// local value for the current user as changes progress.
  public init() {
    counts = [:]
  }
  
  /// Initialize seq from a map of timestamps per user
  private init(_ counts : [UUID : UInt]) {
    self.counts = counts
  }

  /// Generate the next sequence given the id advancing the clock
  public func next(_ id : UUID) -> Seq {
    var next = counts
    next[id] = (next[id] ?? 0) + 1
    return Seq(next)
  }
  
  /// Merge another Seq with this one resulting in the highest shared
  /// set of time values
  public func merge(_ seqs : [Seq]) -> Seq {
    var merge = counts
    for s in seqs {
      for k in s.counts.keys {
        merge[k] = max(s.counts[k] ?? 0, merge[k] ?? 0)
      }
    }
    return Seq(merge)
  }
  
  /// Compare two Seq values for one after the other in the sequence
  public func after(_ s : Seq) -> Bool {
    for k in s.counts.keys {
      if self.counts[k] ?? 0 < s.counts[k] ?? 0 {
        return false
      }
    }
    for k in self.counts.keys {
      if self.counts[k] ?? 0 < s.counts[k] ?? 0 {
        return false
      }
    }
    return true
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(self.counts.keys.count)
    for k in self.counts.keys {
      let value = self.counts[k]
      try container.encode(k)
      try container.encode(value)
    }
  }
  
  public init(from decoder: Decoder) throws {
    self.counts = [:]
    var container = try decoder.unkeyedContainer()
    let n = try container.decode(Int.self)
    for _ in 0..<n {
      let key : UUID = try container.decode(UUID.self)
      let value : Int = try container.decode(Int.self)
      self.counts[key] = UInt(value)
    }
  }
  
  public var sortableString: String {
    let keys = self.counts.keys.sorted { a, b in
      let ast = String(describing: a)
      let bst = String(describing: b)
      return ast <= bst
    }
    return keys.reduce("") { result, k in
      [result, "\(k.uuidString):\(String(format: "%09d", self.counts[k]!))"].joined(separator: ",")
    }
  }
}
