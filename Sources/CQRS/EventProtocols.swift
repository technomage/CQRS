//
//  EventProtocols.swift
//  
//  Protocols for working with events.
//  Created by Michael Latta on 12/10/20.
//

import Foundation

public protocol ListEventWithParent : Event {
  var parent : UUID? { get set }
}

public protocol WithID : Codable, Identifiable where ID == UUID {
  var id : ID { get }
}

public protocol Patchable {
  func patch(map: inout [UUID:UUID]) -> Self?
}
