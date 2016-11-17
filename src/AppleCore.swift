import Foundation

struct AppleCore {

  enum TraceLevel {
    case none
    case entitiesOnly
    case all
  }

  static var traceLevel = TraceLevel.entitiesOnly

  static func traceEntity(_ entityName: String) {
    if traceLevel == .none {
      return
    }

    print("Monkey ---> Entity \(entityName)")
  }

  static func traceID(_ id: String) {
    if traceLevel == .none {
      return
    }

    print("Monkey      ID: \(id)")
  }

  static func traceExisting() {
    if traceLevel == .none {
      return
    }

    print("Monkey      Existing - no update")
  }
  
  static func traceInsert() {
    if traceLevel == .none {
      return
    }

    print("Monkey      Inserting")
  }
  
  static func traceUpdate() {
    if traceLevel == .none {
      return
    }

    print("Monkey      Update")
  }
  
  static func trace(_ message: String?) {
    if let msg = message {
      print("Monkey      \(msg)")
    }
  }
  

}
