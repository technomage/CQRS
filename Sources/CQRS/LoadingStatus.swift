//
//  File.swift
//  
//
//  Created by Michael Latta on 6/26/20.
//

import Foundation
import Combine

@available(iOS 13.0, macOS 10.15, *)
public class LoadingStatus: ObservableObject {
  @Published public var loading = false
  public var cancel : AnyCancellable? = nil
  
  public init() {
    cancel = $loading.sink { v in
      NSLog("@@@@ Change in loading status")
      if v {
        NSLog("@@@@ Showing loading to true")
      }
    }
  }
}
