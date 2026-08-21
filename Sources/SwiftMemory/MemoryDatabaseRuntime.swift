import Database

struct MemoryDatabaseRuntime: Sendable {
    let container: DBContainer
    let contexts: [Base.ID: MemoryContext]
    let authorization: AuthorizationContext
}
