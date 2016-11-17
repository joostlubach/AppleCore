import CoreData
import BrightFutures
import QueryKit
import SwiftyJSON

open class DataManager<T: NSManagedObject> {

  convenience init(context: ManagedObjectContextConvertible) {
    self.init(entityName: NSStringFromClass(T.self), context: context)
  }

  init(entityName: String, context: ManagedObjectContextConvertible) {
    self.entityName = entityName
    self.context = context.managedObjectContext
  }

  open let entityName: String
  open let context:    ManagedObjectContext

  open lazy var entity: NSEntityDescription = {
    return NSEntityDescription.entity(
      forEntityName: self.entityName,
      in: self.context.underlyingContext
      )!
    }()

  /// Finds an object by its ID.
  open func findWithID(_ id: AnyObject) throws -> T? {
    let query = QuerySet<T>(context.underlyingContext, entityName)
    let mapper = DataMapper<NSManagedObject>(entityName: entityName, context: context)

    if let idMapping = mapper.IDMapping {
      let predicate = NSPredicate(format: "\(idMapping.attribute) == %@", argumentArray: [id])
      return try query.filter(predicate).first()
    } else {
      preconditionFailure("\(entityName) does not have an ID mapping")
    }
  }

  open func insert() -> T {
    return T(entity: entity, insertInto: context.underlyingContext)
  }

  /// Deletes all entities.
  open func deleteAll() throws -> Int {
    let querySet = QuerySet<NSManagedObject>(context.underlyingContext, entityName)
    return try querySet.delete()
  }

  // MARK: JSON


  /// Finds or inserts an object from the given JSON. The id is taken from the "id" property.
  open func findOrInsertWithJSON(_ json: JSON, extra: [String: AnyObject?] = [:]) -> T {
    let id: AnyObject = DataMapper<T>(entityName: entityName, context: context).getIDFromJSON(json)
    AppleCore.traceID("\(id)")

    var object = try! findWithID(id)

    if object == nil {
      object = insertWithJSON(json, extra: extra)
    } else {
      AppleCore.traceExisting()
    }

    return object!
  }

  /// Inserts or updates an object from the given JSON. The id is taken from the "id" property.
  open func insertOrUpdateWithJSON(_ json: JSON, extra: [String: AnyObject?] = [:]) -> T {
    let id: AnyObject = DataMapper<T>(entityName: entityName, context: context).getIDFromJSON(json)
    AppleCore.traceID("\(id)")

    var object = try! findWithID(id)

    if object == nil {
      AppleCore.traceInsert()
      object = insert()
    } else {
      AppleCore.traceUpdate()
    }

    return update(object!, withJSON: json, extra: extra)
  }

  /// Inserts an object from the given JSON.
  open func insertWithJSON(_ json: JSON, extra: [String: AnyObject?] = [:]) -> T {
    AppleCore.traceInsert()

    let object = insert()
    return update(object, withJSON: json, extra: extra)
  }

  /// Updates an object from the given JSON.
  open func update(_ object: T, withJSON json: JSON, extra: [String: AnyObject?] = [:]) -> T {
    let mapper = DataMapper<T>(entityName: entityName, context: context)
    mapper.mapJSON(json, toObject: object)

    for (key, value) in extra {
      (object as NSManagedObject).setValue(value, forKey: key)
    }

    return object
  }

  /// Inserts a set of objects from a JSON array.
  open func insertSetWithJSON(_ json: JSON, extra: [String: AnyObject?] = [:], updateExisting: Bool = true, orderOffset: Int = 0) -> [T] {
    var set: [T] = []
    let mapper = DataMapper<T>(entityName: entityName, context: context)

    if let array = json.array {
      var object: T!
      var order = orderOffset

      for node in array {
        AppleCore.traceEntity(entityName)

        if mapper.IDMapping == nil {
          object = insertWithJSON(node, extra: extra)
        } else if updateExisting {
          object = insertOrUpdateWithJSON(node, extra: extra)
        } else {
          object = findOrInsertWithJSON(node, extra: extra)
        }
        if let orderKey = mapper.orderKey {
          (object as NSManagedObject).setValue(order, forKey: orderKey)
        }

        set.append(object)
        order += 1
      }
    } else {
      assertionFailure("Expected array")
    }
    
    return set
  }

}
