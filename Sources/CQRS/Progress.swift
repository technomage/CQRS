//
//  File.swift
//  
//
//  Created by Michael Latta on 6/27/20.
//

import Foundation

@available(iOS 14.0, macOS 11.0, *)
public class Progress : ObservableObject {
  @Published public var progress: Int = 0
  @Published public var total: Int? = nil
  
  public init() {
  }
  
  public init(total: Int?, progress: Int) {
    self.progress = progress
    self.total = total
  }
}
