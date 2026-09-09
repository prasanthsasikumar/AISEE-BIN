import Foundation

/// Locations and (de)serialisation of the local map bundle in Documents:
/// - `greenhouse.arworldmap`  ARWorldMap archive (written by `ARNavigationManager`)
/// - `greenhouse.map.json`    `NavigationMap` graph: names, categories, descriptions, edges, coordinates
/// - `greenhouse.points.f32`  feature-point cloud for the web editor
/// - `greenhouse.version.json` which server version (if any) this bundle corresponds to
struct MapStore {

    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.directory = directory
    }

    var worldMapURL: URL { directory.appendingPathComponent("greenhouse.arworldmap") }
    var mapJSONURL: URL { directory.appendingPathComponent("greenhouse.map.json") }
    var pointCloudURL: URL { directory.appendingPathComponent("greenhouse.points.f32") }
    var versionURL: URL { directory.appendingPathComponent("greenhouse.version.json") }

    var hasSavedMap: Bool { FileManager.default.fileExists(atPath: mapJSONURL.path) }
    var hasSavedWorldMap: Bool { FileManager.default.fileExists(atPath: worldMapURL.path) }

    // MARK: Graph

    func loadMap() -> NavigationMap? {
        guard let data = try? Data(contentsOf: mapJSONURL) else { return nil }
        return try? JSONDecoder().decode(NavigationMap.self, from: data)
    }

    func saveMap(_ map: NavigationMap) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(map).write(to: mapJSONURL, options: [.atomic])
    }

    // MARK: Binary blobs

    func saveWorldMapData(_ data: Data) throws {
        try data.write(to: worldMapURL, options: [.atomic])
    }

    func loadWorldMapData() throws -> Data {
        try Data(contentsOf: worldMapURL)
    }

    func savePointCloud(_ data: Data) throws {
        try data.write(to: pointCloudURL, options: [.atomic])
    }

    func loadPointCloud() -> Data? {
        try? Data(contentsOf: pointCloudURL)
    }

    // MARK: Version record

    func loadVersion() -> LocalMapVersion? {
        guard let data = try? Data(contentsOf: versionURL) else { return nil }
        return try? JSONDecoder().decode(LocalMapVersion.self, from: data)
    }

    func saveVersion(_ version: LocalMapVersion) throws {
        try JSONEncoder().encode(version).write(to: versionURL, options: [.atomic])
    }

    /// Removes the whole bundle.
    func deleteAll() throws {
        for url in [worldMapURL, mapJSONURL, pointCloudURL, versionURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
