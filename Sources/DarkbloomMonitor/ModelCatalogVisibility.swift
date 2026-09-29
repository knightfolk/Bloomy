/// Retired catalog entries are omitted from idle suggestions. A saved, staged,
/// advertised, or live entry remains visible so its status and controls cannot
/// disappear. Raw inventory, configuration, and history remain unchanged.
enum ModelCatalogVisibility {
    private static let retiredIDs: Set<String> = [
        "gemma-4-26b",
        "gemma-4-26b-8bit",
    ]

    static func includes(_ modelID: String, inUse: Bool = false) -> Bool {
        inUse || !retiredIDs.contains(modelID.lowercased())
    }
}
