//
//  ArchiveTest.swift
//  
//
//  Created by Michael Latta on 9/24/20.
//

import Foundation
import XCTest
@testable import CQRS

@available(iOS 14.0, macOS 11.0, *)
final class ArchiveTest: XCTestCase {
  
  override func setUp() {
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
  }
  
  func testArchiving1() throws {
    let v1 = "testing".data(using: .utf8)!
    let ar1 = NSKeyedArchiver(requiringSecureCoding: false)
    ar1.encode(v1, forKey: "EVENTS")
    ar1.finishEncoding()
    let bytes = ar1.encodedData
    //
    let ar2 = try NSKeyedUnarchiver(forReadingFrom: bytes)
    XCTAssert(ar2.containsValue(forKey: "EVENTS"), "Failed to encode data for key")
    let v2 = ar2.decodeObject(forKey: "EVENTS")
    XCTAssertEqual(v1, v2 as! Data, "Failed to get simple string back")
  }
  
  func testArchiving2() throws {
    let v1a = "testing".data(using: .utf8)
    let v1b = "testing".data(using: .utf8)
    let ar1 = NSKeyedArchiver(requiringSecureCoding: false)
    ar1.encode(v1a, forKey: "EVENTS1")
    ar1.encode(v1b, forKey: "EVENTS2")
    ar1.finishEncoding()
    let bytes = ar1.encodedData
    //
    let ar2 = try NSKeyedUnarchiver(forReadingFrom: bytes)
    XCTAssert(ar2.containsValue(forKey: "EVENTS1"), "Failed to encode data for key")
    XCTAssert(ar2.containsValue(forKey: "EVENTS2"), "Failed to encode data for key")
    let v2a = ar2.decodeObject(forKey: "EVENTS1")
    let v2b = ar2.decodeObject(forKey: "EVENTS2")
    XCTAssertEqual(v1a, (v2a as! Data), "Failed to get simple string back")
    XCTAssertEqual(v1b, (v2b as! Data), "Failed to get simple string back")
  }
}
