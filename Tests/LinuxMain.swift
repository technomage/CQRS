import XCTest

import CQRSTests

var tests = [XCTestCaseEntry]()
tests += CQRSTests.allTests()
XCTMain(tests)
