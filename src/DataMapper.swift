import CoreData
import SwiftyJSON

private typealias MappingEntry = (id: StandardMapping?, orderKey: String?, attributes: [Mapping])
private var Mappings:  [String: MappingEntry] = [:]
//private var ConfigurationTokens: [String: dispatch_once_t] = [:]

private func DefaultIDMapping() -> StandardMapping {
  return IntegerMapping("id")
}

public protocol Mapping {

  func mapValueFromJSON(_ json: JSON, toObject object: NSManagedObject, inContext context: ManagedObjectContext)

}

open class CustomMapping<T: NSManagedObject>: Mapping {

  public typealias Handler = (T, _ json: JSON, _ context: ManagedObjectContext) -> Void

  public init(_ handler:  @escaping Handler) {
    self.handler = handler
  }
  public init(_ handler: @escaping (T, _ json: JSON) -> Void) {
    self.handler = { target, json, context in handler(target, json) }
  }
  public init(_ method: @escaping (T) -> (JSON) -> Void) {
    self.handler = { target, json, context in method(target)(json) }
  }

  let handler: Handler

  open func mapValueFromJSON(_ json: JSON, toObject object: NSManagedObject, inContext context: ManagedObjectContext) {
    handler(object as! T, json, context)
  }

}

open class StandardMapping: Mapping {

  public convenience init(_ attribute: String) {
    self.init(attribute, from: StringUtil.underscore(attribute))
  }

  public init(_ attribute: String, from jsonKey: String) {
    self.attribute = attribute
    self.jsonKey = jsonKey
  }

  let jsonKey: String
  let attribute: String

  var skipIfMissing = true

  /// Gets the JSON that contains this attribute.
  func getAttributeJSON(_ json: JSON) -> JSON {
    let parts = jsonKey.characters.split { $0 == "." }.map { String($0) }

    var current = json
    for part in parts {
      if current.type == .null {
        break
      } else {
        current = current[part]
      }
    }

    return current
  }

  func getValueFromJSON(_ json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    return nil
  }

  open func mapValueFromJSON(_ json: JSON, toObject object: NSManagedObject, inContext context: ManagedObjectContext) {
    let value: AnyObject? = getValueFromJSON(json, context: context)
    object.setValue(value, forKey: attribute)
  }

}

open class NumberMapping: StandardMapping {

  override func getValueFromJSON(_ json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    let attributeJSON = getAttributeJSON(json)

    if let number = attributeJSON.number {
      return getNumber(number)
    } else if attributeJSON.type == .null {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected number")
      return nil
    }
  }

  func getNumber(_ number: NSNumber) -> AnyObject {
    return 0 as AnyObject
  }

}

open class IntegerMapping: NumberMapping {
  override func getNumber(_ number: NSNumber) -> AnyObject {
    return number.intValue as AnyObject
  }
}
open class DoubleMapping: NumberMapping {
  override func getNumber(_ number: NSNumber) -> AnyObject {
    return number.doubleValue as AnyObject
  }
}
open class BooleanMapping: NumberMapping {
  override func getNumber(_ number: NSNumber) -> AnyObject {
    return number.boolValue as AnyObject
  }
}

open class StringMapping: StandardMapping {

  override func getValueFromJSON(_ json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    let attributeJSON = getAttributeJSON(json)

    if let string = attributeJSON.string {
      return string as AnyObject?
    } else if attributeJSON.type == .null {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected string")
      return nil
    }
  }

}

public protocol CaseMappable {
  associatedtype MappedType

  var mappedValue: MappedType { get }
}

open class CaseMapping<T: CaseMappable>: StringMapping where T.MappedType: AnyObject {

  public convenience init(_ attribute: String, cases: [String: T], defaultCase: T? = nil) {
    self.init(attribute, from: StringUtil.underscore(attribute), cases: cases, defaultCase: defaultCase)
  }

  public init(_ attribute: String, from jsonKey: String, cases: [String: T], defaultCase: T? = nil) {
    self.cases = cases
    self.defaultCase = defaultCase
    super.init(attribute, from: jsonKey)
  }

  let cases: [String: T]
  let defaultCase: T?

  override func getValueFromJSON(_ json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    let stringOrNil = super.getValueFromJSON(json, context: context) as? String

    if let string = stringOrNil, let value = cases[string] {
      return value.mappedValue
    } else {
      return defaultCase?.mappedValue
    }
  }

}

open class DateMapping: StandardMapping {

  var dateFormats = [
    "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
    "yyyy-MM-dd'T'HH:mm:ssZ"
  ]
  var locale: Locale   = Locale(identifier: "en_US_POSIX")

  override func getValueFromJSON(_ json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    let attributeJSON = getAttributeJSON(json)

    if let string = attributeJSON.string {
      let formatter        = DateFormatter()
      formatter.locale     = locale

      for format in dateFormats {
        formatter.dateFormat = format
        if let date = formatter.date(from: string) {
          return date as AnyObject?
        }
      }
      return nil
    } else if let number = attributeJSON.number {
      let timestamp = number.doubleValue
      return Date(timeIntervalSince1970: timestamp) as AnyObject?
    } else if attributeJSON.type == .null {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected string or number")
      return nil
    }
  }

}

open class Base64Mapping: StringMapping {

  override func getValueFromJSON(_ json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    if let string = super.getValueFromJSON(json, context: context) as? String {
      let data = Data(base64Encoded: string, options: [])
      if data == nil {
        assertionFailure("Key `\(jsonKey)`: invalid Base64 string")
      }
      return data as AnyObject?
    } else {
      return nil
    }
  }

}

open class ToOneRelationshipMapping<T: NSManagedObject>: StandardMapping {

  convenience init(_ attribute: String, updateExisting: Bool = true) {
    self.init(attribute, from: StringUtil.underscore(attribute), updateExisting: updateExisting)
  }

  init(_ attribute: String, from jsonKey: String, ordered: Bool = false, updateExisting: Bool = true) {
    self.updateExisting = updateExisting
    super.init(attribute, from: jsonKey)
  }

  let updateExisting: Bool

  override func getValueFromJSON(_ json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    let attributeJSON = getAttributeJSON(json)

    if attributeJSON.type == .dictionary {
      let manager = DataManager<T>(context: context)
      if updateExisting {
        return manager.insertOrUpdateWithJSON(attributeJSON)
      } else {
        return manager.findOrInsertWithJSON(attributeJSON)
      }
    } else if attributeJSON.type == .null {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected JSON dictionary")
      return nil
    }
  }

}

open class ToManyRelationshipMapping<T: NSManagedObject>: StandardMapping {

  public convenience init(_ attribute: String, ordered: Bool = false, updateExisting: Bool = true) {
    self.init(attribute, from: StringUtil.underscore(attribute), ordered: ordered, updateExisting: updateExisting)
  }

  public init(_ attribute: String, from jsonKey: String, ordered: Bool = false, updateExisting: Bool = true) {
    self.ordered = ordered
    self.updateExisting = updateExisting
    super.init(attribute, from: jsonKey)
  }

  let ordered: Bool
  let updateExisting: Bool

  override func getValueFromJSON(_ json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    let attributeJSON = getAttributeJSON(json)

    if attributeJSON.type == .array {
      let manager = DataManager<T>(context: context)
      return manager.insertSetWithJSON(attributeJSON, updateExisting: updateExisting) as AnyObject?
    } else if attributeJSON.type == .null {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected JSON array")
      return nil
    }
  }

  override open func mapValueFromJSON(_ json: JSON, toObject object: NSManagedObject, inContext context: ManagedObjectContext) {
    if let array = getValueFromJSON(json, context: context) as? [T] {
      if ordered {
        object.setValue(NSOrderedSet(array: array), forKey: attribute)
      } else {
        object.setValue(NSSet(array: array), forKey: attribute)
      }
    } else if !skipIfMissing {
      object.setValue(NSSet(), forKey: attribute)
    }
  }

}

open class RelatedObjectIDMapping<T: NSManagedObject>: StandardMapping {

  public init(_ attribute: String) {
    super.init(attribute, from: RelatedObjectIDMapping<T>.defaultJSONKey(attribute))
  }

  public override init(_ attribute: String, from jsonKey: String) {
    super.init(attribute, from: jsonKey)
  }

  class func defaultJSONKey(_ attribute: String) -> String {
    return StringUtil.underscore(attribute) + "_id"
  }

  override func getValueFromJSON(_ json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    let entityName = NSStringFromClass(T.self)
    let manager = DataManager<NSManagedObject>(entityName: entityName, context: context)

    let attributeJSON = getAttributeJSON(json)

    var object: NSManagedObject!

    if let number = attributeJSON.number {
      object = try! manager.findWithID(number.intValue as AnyObject)
    } else if let string = attributeJSON.string {
      object = try! manager.findWithID(string as AnyObject)
    } else if attributeJSON.type == .null {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected JSON array")
    }

    if object != nil {
      return object
    } else {
      assertionFailure("Key `\(jsonKey)`: \(entityName) with ID \(attributeJSON.rawString()!) not found")
      return nil
    }
  }

}

open class DataMapper<T: NSManagedObject> {

  convenience init(context: ManagedObjectContextConvertible) {
    self.init(entityName: NSStringFromClass(T.self), context: context)
  }

  init(entityName: String, context: ManagedObjectContextConvertible) {
    self.entityName = entityName
    self.context    = context.managedObjectContext
  }

  open let entityName: String
  let context: ManagedObjectContext

  func mapJSON(_ json: JSON, toObject object: NSManagedObject) {
    // Map ID.
    if let mapping = IDMapping {
      mapping.mapValueFromJSON(json, toObject: object, inContext: context)
    }

    // Map other attributes.
    for mapping in attributeMappings {
      mapping.mapValueFromJSON(json, toObject: object, inContext: context)
    }
  }

  func getIDFromJSON(_ json: JSON) -> AnyObject! {
    if let mapping = IDMapping {
      return mapping.getValueFromJSON(json, context: context)!
    } else {
      assertionFailure("\(entityName) has no ID mapping")
      return nil
    }
  }


  // MARK: - Matadata

  var attributeMappings: [Mapping] {
    assert(entityName != "NSManagedObject", "you need a specialized version of DataMapper")

    if let entry = Mappings[entityName] {
      return entry.attributes
    } else {
      return []
    }
  }

  var IDMapping: StandardMapping? {
    assert(entityName != "NSManagedObject", "you need a specialized version of DataMapper")

    if let entry = Mappings[entityName] {
      return entry.id
    } else {
      return DefaultIDMapping()
    }
  }

  var orderKey: String? {
    assert(entityName != "NSManagedObject", "you need a specialized version of DataMapper")

    if let entry = Mappings[entityName] {
      return entry.orderKey
    } else {
      return nil
    }
  }

  open class func addMapping<TMapping: Mapping>(_ mapping: TMapping) {
    let entityName = NSStringFromClass(T.self)

    if Mappings[entityName] == nil {
      Mappings[entityName] = (id: DefaultIDMapping(), orderKey: nil, attributes: [])
    }

    Mappings[entityName]!.attributes.append(mapping)
  }

  open class func mapIDWith(_ mapping: StandardMapping?) {
    let entityName = NSStringFromClass(T.self)

    if Mappings[entityName] == nil {
      Mappings[entityName] = (id: DefaultIDMapping(), orderKey: nil, attributes: [])
    }

    Mappings[entityName]!.id = mapping
  }

  open class func mapOrderTo(_ key: String?) {
    let entityName = NSStringFromClass(T.self)

    if Mappings[entityName] == nil {
      Mappings[entityName] = (id: DefaultIDMapping(), orderKey: nil, attributes: [])
    }
    
    Mappings[entityName]!.orderKey = key
  }
  
}
