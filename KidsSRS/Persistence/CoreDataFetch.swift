import CoreData

extension NSManagedObjectContext {
    /// Fetch a single managed object of `entityName` whose `id` UUID attribute
    /// matches. Shared by the repositories so the by-id lookup isn't duplicated.
    func fetchFirst<T: NSManagedObject>(_ type: T.Type,
                                        entityName: String,
                                        id: UUID) throws -> T? {
        let request = NSFetchRequest<T>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try fetch(request).first
    }
}
