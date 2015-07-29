//  Stack.swift
//  AppleCore
//
//  Created by Joost Lubach on 31/10/14.
//  Copyright (c) 2014 Joost Lubach. All rights reserved.
//

import CoreData
import QueryKit
import BrightFutures

/// A class encapsulating an entire core data stack, with support for background contexts.
public class CoreDataStack {

  /// Initializes the stack with a SQLLite store at the given URL and the given managed object model.
  public init?(storeURL: NSURL, managedObjectModel model: NSManagedObjectModel) {
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
  public func cleanUp() {
    do {
      try mainContext.saveChanges()
    } catch _ {
    }
  }

  // MARK: Properties

  /// The persistent store coordinator.
  let persistentStoreCoordinator: NSPersistentStoreCoordinator

  /// The managed object context associated with the main thread.
  public lazy var mainContext: ManagedObjectContext = {
    let context = ManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
    context.underlyingContext.persistentStoreCoordinator = self.persistentStoreCoordinator
    return context
  }()

  /// Creates a new background context.
  ///
  /// - parameter isolated:   Set to true to created an isolated thread, which does not permeate its changes
  ///                    to the main context.
  public func newBackgroundContext(isolated: Bool = false) -> ManagedObjectContext {
    if isolated {
      return ManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    } else {
      return ManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType, parentContext: mainContext)
    }
  }

  // MARK: - Convenience accessors

  /// Named representation of commonly used contexts.
  public enum NamedObjectContext {

    /// The main context.
    case Main

    /// A new background (private queue) context.
    case Background

    /// A new isolated background context.
    case Isolated

  }

  /// Saves changes asynchronously using the given block on the given context.
  public func save(context context: NamedObjectContext, block: (ManagedObjectContext) -> Void) -> Future<Void> {
    return namedContext(context).save(block)
  }
  public func save(block: (ManagedObjectContext) -> Void) -> Future<Void> {
    return save(context: .Background, block: block)
  }

  /// Saves changes synchronously using the given block on the given context.
  public func saveAndWait(context context: NamedObjectContext, block: (ManagedObjectContext) -> Void) throws {
    try namedContext(context).saveAndWait(block)
  }
  public func saveAndWait(block: (ManagedObjectContext) -> Void) throws {
    try saveAndWait(context: .Background, block: block)
  }

  /// Creates a new query for the given type.
  public func query<T: NSManagedObject>(type: T.Type, context: NamedObjectContext = .Main) -> QuerySet<T> {
    return namedContext(context).query(type)
  }

  /// Creates a data manager for the given type.
  public func manager<T: NSManagedObject>(type: T.Type, context: NamedObjectContext = .Main) -> DataManager<T> {
    return namedContext(context).manager(type)
  }

  /// Converts a named context into an actual ManagedObjectContext object.
  func namedContext(name: NamedObjectContext) -> ManagedObjectContext {
    switch name {
    case .Main:
      return mainContext
    case .Background:
      return newBackgroundContext()
    case .Isolated:
      return newBackgroundContext(true)
    }
  }

  // MARK: - Utility

  /// Loads the managed object model for the given name.
  public static func managedObjectModelForName(name: String) -> NSManagedObjectModel {
    // The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
    let modelURL = NSBundle.mainBundle().URLForResource(name, withExtension: "momd")!
    return NSManagedObjectModel(contentsOfURL: modelURL)!
  }

  /// Determines a default store URL for a store with the given name.
  public static func defaultStoreURLWithName(name: String) -> NSURL {
    let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
    let applicationDocumentsDirectory = urls[urls.count-1] 

    return applicationDocumentsDirectory.URLByAppendingPathComponent("\(name).sqlite")
  }

  /// Tries to create a persistent store coordinator at the given URL, setting it up using the given
  /// managed object model.
  public static func createPersistentStoreCoordinator(storeURL storeURL: NSURL, usingModel model: NSManagedObjectModel) -> NSPersistentStoreCoordinator? {
    var error: NSError? = nil

    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    do {
      try coordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: nil)
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
