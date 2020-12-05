//
//  IndexedAggregator.swift
//  Ladi
//
//  Created by Michael Latta on 10/4/19.
//  Copyright © 2019 TechnoMage, Michael Latta. All rights reserved.
//

import Foundation
import Combine

@available(iOS 14.0, macOS 11.0, *)
open class IndexedAggregator<E : ListEntry, R : Hashable&Codable&RoleEnum> : ListAggregator<E,R>
  where E : Identifiable, E.ID == UUID
{
  private var cache : [UUID : E]? = nil
  
  open override func receive(_ input: Event) -> Subscribers.Demand {
    cache = nil
    return super.receive(input)
  }
  
  public var dict : Dictionary<UUID, E> {
    get {
      guard cache == nil else { return cache! }
      var result : [UUID:E] = [:]
      self.objAggs.values.forEach { agg in
        if let o = agg.obj {
          result[o.id] = o
        }
      }
      return result
    }
  }

  public override init() {
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
  
  public init(store : UndoableEventStore) {
    super.init()
    self.store = store
    self.subscribeToStore()
  }
  
  public func named(_ name : String) -> E? {
    return self.list.first(where: { f in
      if let fn = f as? Named {
        return fn.name == name
      } else {
        return false
      }
    })
  }
}
