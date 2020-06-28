//
//  File.swift
//  
//
//  Created by Michael Latta on 6/27/20.
//

import Foundation

@available(iOS 13.0, macOS 10.15, *)
public class Progress : ObservableObject {
  @Published public var progress: Int = 0
  @Published public var total: Int = 0
  
  public init() {
  }
  
  public init(total: Int, progress: Int) {
    self.progress = progress
    self.total = total
  }
}
