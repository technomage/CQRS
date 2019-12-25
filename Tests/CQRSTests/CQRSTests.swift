import XCTest
@testable import CQRS

@available(iOS 13.0, *)
final class CQRSTests: XCTestCase {
  struct Ref {
    let id = UUID()
    var val : String = ""
  }
  
  override func setUp() {
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
  }
  
  func testEventStore() {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
    let subj = Ref()
    let store = EventStore()
    var cnt : Int = 0
    var last : Event? = nil
    
    let sub = store.log.sink { evt in
      last = evt
      cnt += 1
    }
    XCTAssertEqual(0, cnt, "Expected to start at 0")
    XCTAssertEqual(0, store.log.events.count, "Log should be empty at the start")
    XCTAssertNil(last, "Should have been nil to start")
    let e = SetEvent<Ref,String>(project: UUID(),
                                 subject: subj.id,
                                 path: \.val,
                                 value: "This is a test",
                                 prior: "")
    store.append(e)
    XCTAssertEqual(1, store.event!.seq, "Store starts at 1 after change")
    XCTAssertEqual(1, store.log.events.count, "Log should have one event after one submitted")
    XCTAssertEqual(1, cnt, "Number of events not 1 after one append")
    XCTAssertNotNil(last, "Failed to set last event")
    XCTAssertEqual(1, last!.seq, "Last starts at 1 after change")
    for _ in 0..<10_000 {
      var edelta = e
      edelta.id = UUID()
      store.append(edelta)
    }
    XCTAssertEqual(10_001, store.event!.seq, "Store has 10,001 after thta many")
    XCTAssertEqual(10_001, store.log.events.count, "Log should have 10,001 after that many submitted")
    XCTAssertEqual(10_001, last!.seq, "Store has 10,001 after that many submitted")
    XCTAssertEqual(10_001, cnt, "Count of events not as expected")
    sub.cancel()
    var cnt2 = 0
    var cnt3 = 0
    let sub2 = store.log.sink { e in
      cnt2 += 1
      XCTAssertEqual(e.seq!, cnt2)
    }
    let sub3 = store.log.sink { e in
      cnt3 += 1
      XCTAssertEqual(e.seq!, cnt3)
    }
    XCTAssertEqual(10_001, cnt, "Count of events not as expected")
    XCTAssertEqual(10_001, cnt2, "Count for sink not expected")
    store.append(SetEvent<Ref,String>(project: UUID(),
                                      subject: UUID(),
                                      path: \Ref.val,
                                      value: "",
                                      prior: ""))
    XCTAssertEqual(10_002, cnt2, "Count for sink not expected")
    XCTAssertEqual(10_002, cnt2, "Count for sink not expected")
    XCTAssertEqual(10_002, cnt2, "Count for sink not expected")
    //
    sub3.cancel()
    sub2.cancel()
  }
}
