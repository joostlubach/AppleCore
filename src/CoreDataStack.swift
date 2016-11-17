import CoreData
import QueryKit
import BrightFutures

/// A class encapsulating an entire core data stack, with support for background contexts.
open class CoreDataStack {

  /// Initializes the stack with a SQLLite store at the given URL and the given managed object model.
  public init?(storeURL: URL, managedObjectModel model: NSManagedObjectModel) {
    if let coordinator = CoreDataStack.createPersistentStoreCoordinator(storeURL: storeURL, usingModel: model) {
      persistentStoreCoordinator = coordinator
    } else {
      // Note: I don't know why the stored property has to be initialized before returning nil. I'm returning nil!!
      persistentStoreCoordinator = NSPersistentStoreCoordinator()
      return nil
    }
  }

  /// Initializes the stack with a SQLLite store at a default location, and a managed object model.
  ///
  /// - parameter name:   The name of both the SQLLite store (<name>.sqllite) and the managed object model.
  public convenience init?(name: String) {
    self.init(storeURL: CoreDataStack.defaultStoreURLWithName(name), managedObjectModel: CoreDataStack.managedObjectModelForName(name))
  }

  // MARK: Clean up

  /// Cleans up when the application exits.
  open func cleanUp() {
    do {
      try mainContext.saveChanges()
    } catch _ {
    }
  }

  // MARK: Properties

  /// The persistent store coordinator.
  let persistentStoreCoordinator: NSPersistentStoreCoordinator

  /// The managed object context associated with the main thread.
  open lazy var mainContext: ManagedObjectContext = {
    let context = ManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    context.underlyingContext.persistentStoreCoordinator = self.persistentStoreCoordinator
    return context
  }()

  /// Creates a new background context.
  ///
  /// - parameter isolated:   Set to true to created an isolated thread, which does not permeate its changes
  ///                    to the main context.
  open func newBackgroundContext(_ isolated: Bool = false) -> ManagedObjectContext {
    if isolated {
      return ManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    } else {
      return ManagedObjectContext(concurrencyType: .privateQueueConcurrencyType, parentContext: mainContext)
    }
  }

  /// Creates a new context on the main thread.
  ///
  /// - parameter isolated:   Set to true to created an isolated thread, which does not permeate its changes
  ///                    to the main context.
  open func newMainContext(_ isolated: Bool = false) -> ManagedObjectContext {
    if isolated {
      return ManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    } else {
      return ManagedObjectContext(concurrencyType: .mainQueueConcurrencyType, parentContext: mainContext)
    }
  }

  /// Creates a new context on the main thread, with the given context as parent context.
  open func newMainContext(_ parentContext: ManagedObjectContext) -> ManagedObjectContext {
    return ManagedObjectContext(concurrencyType: .mainQueueConcurrencyType, parentContext: parentContext)
  }

  // MARK: - Convenience accessors

  /// Named representation of commonly used contexts.
  public enum NamedObjectContext {

    /// The main context.
    case main

    /// A new background (private queue) context.
    case background

    /// A new isolated background context.
    case isolated

  }

  /// Creates a new query for the given type.
  open func query<T: NSManagedObject>(_ type: T.Type, context: NamedObjectContext = .main) -> QuerySet<T> {
    return namedContext(context).query(type)
  }

  /// Creates a data manager for the given type.
  open func manager<T: NSManagedObject>(_ type: T.Type, context: NamedObjectContext = .main) -> DataManager<T> {
    return namedContext(context).manager(type)
  }

  /// Converts a named context into an actual ManagedObjectContext object.
  func namedContext(_ name: NamedObjectContext) -> ManagedObjectContext {
    switch name {
    case .main:
      return mainContext
    case .background:
      return newBackgroundContext()
    case .isolated:
      return newBackgroundContext(true)
    }
  }

  // MARK: - Utility

  /// Loads the managed object model for the given name.
  open static func managedObjectModelForName(_ name: String) -> NSManagedObjectModel {
    // The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
    let modelURL = Bundle.main.url(forResource: name, withExtension: "momd")!
    return NSManagedObjectModel(contentsOf: modelURL)!
  }

  /// Determines a default store URL for a store with the given name.
  open static func defaultStoreURLWithName(_ name: String) -> URL {
    let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let applicationDocumentsDirectory = urls[urls.count-1] 

    return applicationDocumentsDirectory.appendingPathComponent("\(name).sqlite")
  }

  /// Tries to create a persistent store coordinator at the given URL, setting it up using the given
  /// managed object model.
  open static func createPersistentStoreCoordinator(storeURL: URL, usingModel model: NSManagedObjectModel) -> NSPersistentStoreCoordinator? {
    var error: NSError? = nil

    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    do {
      try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
    } catch let error1 as NSError {
      error = error1
    }

    if error == nil {
      return coordinator
    } else {
      return nil
    }
  }
  
}
