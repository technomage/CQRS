//
//  IndexedAggregator.swift
//  Ladi
//
//  Created by Michael Latta on 10/4/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

@available(iOS 13.0, *)
open class IndexedAggregator<E : ListEntry, R : Hashable&Codable> : ListAggregator<E,R> {
  public var dict : Dictionary<UUID, E> {
    get {
      var result : [UUID:E] = [:]
      self.objAggs.values.forEach { agg in
        result[agg.obj!.id] = agg.obj!
      }
      return result
    }
  }

  required public init() {
    super.init()
  }
  
  public convenience init(filter: @escaping ListFilterClosure) {
    self.init()
    self.filter = filter
  }
  
  public convenience init(config : @escaping ChildAggregatorClosure) {
    self.init()
    self.childConfig = config
  }
  
  public convenience init(config : @escaping ChildAggregatorClosure,
                   filter: @escaping ListFilterClosure) {
    self.init()
    self.childConfig = config
    self.filter = filter
  }
  
  public convenience init(role: R) {
    self.init()
    self.role = role
  }
  
  public convenience init(role: R, store: UndoableEventStore) {
    self.init()
    self.role = role
    self.store = store
    self.subscribeToStore()
  }
  
  public convenience init(role: R, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
  }
  
  public convenience init(role: R, store: UndoableEventStore, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
    self.store = store
    self.subscribeToStore()
  }
  
  public convenience init(role: R, store: UndoableEventStore, parent: UUID, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
    self.parent = parent
    self.store = store
    self.subscribeToStore()
  }
  
  public convenience init(role: R, store: UndoableEventStore, parent: UUID, config: @escaping ChildAggregatorClosure, filter: @escaping ListFilterClosure) {
    self.init()
    self.role = role
    self.filter = filter
    self.childConfig = config
    self.parent = parent
    self.store = store
    self.subscribeToStore()
  }
  
  public convenience init(role: R, config : @escaping ChildAggregatorClosure) {
    self.init()
    self.role = role
    self.childConfig = config
  }
  
  public convenience init(store : UndoableEventStore) {
    self.init()
    self.store = store
    self.subscribeToStore()
  }
}
