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

@available(iOS 14.0, macOS 11.0, *)
public class LoadingStatus: ObservableObject {
  @Published public var loading : LoadingState = .new
  @Published public var showLoading = false
  var cancel : AnyCancellable?
  public init() {
    self.cancel = self.$loading.sink { l in
//      print("@@@@ Updated loading status: \(l == .loading)")
      self.showLoading = l == .loading
    }
  }
}

@available(iOS 14.0, macOS 11.0, *)
public enum Loading {
  case newFile
  case loadingFile
  case startLoadingFile
}
