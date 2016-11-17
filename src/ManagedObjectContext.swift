import CoreData
import BrightFutures
import QueryKit

/// Wrapper around NSManagedObjectContext.
open class ManagedObjectContext: NSObject {

  /// Initializes the context with the given underlying context.
  public init(underlyingContext: NSManagedObjectContext) {
    self.underlyingContext = underlyingContext
  }

  /// Initializes the context with a new underlying context with the given options.
  public convenience init(concurrencyType: NSManagedObjectContextConcurrencyType = .privateQueueConcurrencyType, parentContext: ManagedObjectContext? = nil) {
    self.init(underlyingContext: NSManagedObjectContext(concurrencyType: concurrencyType))

    if let context = parentContext {
      underlyingContext.performAndWait {
        self.underlyingContext.parent = context.underlyingContext
      }
    }
  }

  deinit {
    if isObserver {
      NotificationCenter.default.removeObserver(self)
    }
  }

  // MARK: Properties

  /// The underlying NSManagedObjectContext instance.
  open let underlyingContext: NSManagedObjectContext

  /// Creates a QuerySet of given type for this context.
  open func query<T: NSManagedObject>(_ type: T.Type) -> QuerySet<T> {
    return QuerySet<T>(underlyingContext, NSStringFromClass(T.self))
  }

  /// Creates a data manager of given type for this context.
  open func manager<T: NSManagedObject>(_ type: T.Type) -> DataManager<T> {
    return DataManager<T>(context: self)
  }

  // MARK: - Operations

  open func insert<T: NSManagedObject>(_ type: T.Type) -> T {
    let entityName = NSStringFromClass(T.self)
    let entity = NSEntityDescription.entity(forEntityName: entityName, in: underlyingContext)!
    return T(entity: entity, insertInto: underlyingContext)
  }

  /// Performs a block on this context, passing this context.
  open func performBlock(_ block: @escaping () throws -> Void) -> Future<Void, NSError> {
    let promise = Promise<Void, NSError>()

    underlyingContext.perform {
      do {
        try block()
        promise.success()
      } catch let error as NSError {
        promise.failure(error)
      }
    }

    return promise.future
  }

  /// Performs a throwing block on this context, and waits until execution is finished.
  open func performBlockAndWait(_ block: @escaping () throws -> Void) throws {
    var internalError: NSError?

    underlyingContext.performAndWait {
      do {
        try block()
      } catch let error as NSError {
        internalError = error
      }
    }

    if let error = internalError {
      throw error
    }
  }

  /// Performs a non-throwing block on this context, and waits until execution is finished.
  open func performBlockAndWait(_ block: @escaping () -> Void) {
    underlyingContext.performAndWait(block)
  }

  /// Saves data asynchronously using a block.
  ///
  /// - returns: A future used to obtain a result status with.
  open func save(_ block: @escaping (ManagedObjectContext) throws -> Void) -> Future<Void, NSError> {
    let promise = Promise<Void, NSError>()

    underlyingContext.perform {
      do {
        try block(self)
        try self.saveChanges()
        promise.success()
      } catch let error as NSError {
        promise.failure(error)
      }
    }

    return promise.future
  }

  /// Saves data synchronously.
  open func saveAndWait(_ block: @escaping (ManagedObjectContext) throws -> Void) throws {
    var internalError: NSError?

    underlyingContext.performAndWait {
      do {
        try block(self)
        try self.saveChanges()
      } catch let error as NSError {
        internalError = error
      }
    }

    if let error = internalError {
      throw error
    }
  }

  /// Saves any changes made in the context.
  open func saveChanges(_ saveParents: Bool = true) throws {
    if !underlyingContext.hasChanges { return }

    if saveParents {
      var context: NSManagedObjectContext! = underlyingContext
      while context != nil {
        try context.save()
        context = context.parent
      }
    } else {
      try underlyingContext.save()
    }
  }

  /// Deletes an object from this context.
  open func deleteObject(_ object: NSManagedObject) {
    underlyingContext.delete(object)
  }

  /// Gets a copy of the given managed object in the current context.
  open func get<T: NSManagedObject>(_ object: T) -> T {
    let objectID = object.objectID
    return underlyingContext.object(with: objectID) as! T
  }

  // MARK: - Synchronization

  var isObserver = false
  var contextsToMergeChangesInto: [ManagedObjectContext] = []

  /// Makes sure that when this context is saved, its changed are merged into the target context.
  func mergeChangesInto(_ context: ManagedObjectContext) {
    if !isObserver {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(ManagedObjectContext.contextDidSave(_:)),
        name: NSNotification.Name.NSManagedObjectContextDidSave,
        object: underlyingContext
      )
      isObserver = true
    }

    contextsToMergeChangesInto.append(context)
  }

  func contextDidSave(_ notification: Notification) {
    for context in contextsToMergeChangesInto {
      context.underlyingContext.perform {
        context.underlyingContext.mergeChanges(fromContextDidSave: notification)
      }
    }
  }

}

protocol ManagedObjectContextConvertible {
  var managedObjectContext: ManagedObjectContext { get }
}

extension ManagedObjectContext: ManagedObjectContextConvertible {

  var managedObjectContext: ManagedObjectContext {
    return self
  }

}

extension NSManagedObjectContext: ManagedObjectContextConvertible {

  var managedObjectContext: ManagedObjectContext {
    return ManagedObjectContext(underlyingContext: self)
  }
  
}
