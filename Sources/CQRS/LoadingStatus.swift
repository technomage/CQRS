//
//  File.swift
//  
//
//  Created by Michael Latta on 6/26/20.
//

import Foundation
import Combine

public enum LoadingState {
  case new
  case loading
  case done
}

@available(iOS 13.0, macOS 10.15, *)
public class LoadingStatus: ObservableObject {
  @Published public var loading : LoadingState = .new
  @Published public var showLoading = false
  var cancel : AnyCancellable?
  public init() {
    self.cancel = self.$loading.sink { l in
      self.showLoading = l == .loading
    }
  }
}

@available(iOS 13.0, macOS 10.15, *)
public enum Loading {
  case newFile
  case loadingFile
  case startLoadingFile
}
