import Database

/// Layer configuration, selection, authorization, and storage-layout errors.
public enum MemoryLayerError: Error, Sendable, Equatable {
    case emptyName(Base.ID)
    case emptyLayerSet
    case emptyLayerSelection
    case duplicateLayer(Base.ID)
    case defaultLayerNotConfigured(Base.ID)
    case layerNotConfigured(Base.ID)
    case authenticatedPrincipalRequired
}
