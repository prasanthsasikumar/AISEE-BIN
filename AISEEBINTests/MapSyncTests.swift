import XCTest
import simd
@testable import AISEEBIN

final class MapSyncTests: XCTestCase {

    // MARK: Point cloud codec

    func testPointCloudRoundTripsAsLittleEndianFloat32Triples() {
        let points = [SIMD3<Float>(1, 2, 3), SIMD3<Float>(-0.5, 0.25, -7)]
        let data = PointCloudCodec.encode(points)
        XCTAssertEqual(data.count, 24)
        XCTAssertEqual(PointCloudCodec.decode(data), points)
        // First float, little-endian 1.0f = 00 00 80 3F
        XCTAssertEqual(Array(data.prefix(4)), [0x00, 0x00, 0x80, 0x3F])
    }

    func testPointCloudDecodeIgnoresTrailingPartialTriple() {
        var data = PointCloudCodec.encode([SIMD3<Float>(1, 1, 1)])
        data.append(contentsOf: [0, 0, 0, 0])
        XCTAssertEqual(PointCloudCodec.decode(data).count, 1)
    }

    // MARK: Remote version rows

    func testDecodesRestRowIncludingGraph() throws {
        let json = """
        [{"id":"7b1c","map_slug":"default","version":3,"source":"web","note":"moved orchid",
          "graph":{"name":"Greenhouse","pois":[{"id":"a","name":"A","x":1,"z":-2}],"edges":[]},
          "worldmap_path":"default/v2/greenhouse.arworldmap","pointcloud_path":"default/v2/points.f32",
          "point_count":1234,"created_at":"2026-09-08T06:00:00.123456+00:00"}]
        """
        let rows = try JSONDecoder.supabase.decode([RemoteMapVersion].self, from: Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].version, 3)
        XCTAssertEqual(rows[0].source, .web)
        XCTAssertEqual(rows[0].graph.pois.first?.planarPosition, SIMD2<Float>(1, -2))
        XCTAssertEqual(rows[0].pointCount, 1234)
    }

    func testRemoteIsNewerThanLocalComparison() {
        let local = LocalMapVersion(version: 2, source: .ios, updatedAt: Date())
        XCTAssertTrue(MapSyncService.shouldDownload(remoteVersion: 3, local: local))
        XCTAssertFalse(MapSyncService.shouldDownload(remoteVersion: 2, local: local))
        XCTAssertTrue(MapSyncService.shouldDownload(remoteVersion: 1, local: nil))
    }

    // MARK: Map listing

    func testAvailableMapsKeepsOnlyTheHighestVersionOfEachSlug() throws {
        // Ordered the way the REST query asks for it: slug ascending, version descending.
        let json = """
        [{"map_slug":"default","version":4,"source":"web","created_at":"2026-09-08T13:38:11.847349+00:00","point_count":13104,"name":"Greenhouse"},
         {"map_slug":"default","version":1,"source":"web","created_at":"2026-09-08T07:01:25.365678+00:00","point_count":0,"name":"Sample Greenhouse"},
         {"map_slug":"hussel","version":2,"source":"web","created_at":"2026-09-09T05:34:45.263043+00:00","point_count":6178,"name":"Hussel"},
         {"map_slug":"hussel","version":1,"source":"ios","created_at":"2026-09-09T05:21:35.252119+00:00","point_count":6178,"name":"Hussel"}]
        """
        let rows = try JSONDecoder.supabase.decode([RemoteMapSummary].self, from: Data(json.utf8))
        let maps = MapSyncService.latestPerSlug(rows)

        XCTAssertEqual(maps.map(\.slug), ["default", "hussel"])
        XCTAssertEqual(maps.map(\.version), [4, 2])
        // The name comes from the newest version, not the one the map was seeded with.
        XCTAssertEqual(maps[0].name, "Greenhouse")
        XCTAssertEqual(maps[0].pointCount, 13104)
        XCTAssertEqual(maps[1].source, .web)
    }

    func testAvailableMapsIsNotFooledByRowsArrivingOutOfOrder() {
        let rows = [
            RemoteMapSummary(slug: "hussel", name: "Hussel", version: 1, source: .ios, pointCount: 10, createdAt: Date(timeIntervalSince1970: 20)),
            RemoteMapSummary(slug: "default", name: "Greenhouse", version: 4, source: .web, pointCount: 30, createdAt: Date(timeIntervalSince1970: 40)),
            RemoteMapSummary(slug: "hussel", name: "Hussel v2", version: 2, source: .web, pointCount: 10, createdAt: Date(timeIntervalSince1970: 30)),
        ]
        let maps = MapSyncService.latestPerSlug(rows)
        XCTAssertEqual(maps.map(\.slug), ["default", "hussel"])
        XCTAssertEqual(maps.map(\.version), [4, 2])
        XCTAssertEqual(maps[1].name, "Hussel v2")
    }

    func testAvailableMapsOnAnEmptyServerIsEmpty() {
        XCTAssertTrue(MapSyncService.latestPerSlug([]).isEmpty)
    }

    // MARK: Map names and slugs

    func testSlugDerivesWebEditorStyleKeyFromMapName() {
        XCTAssertEqual(ServerConfig.slug(from: "Home"), "home")
        XCTAssertEqual(ServerConfig.slug(from: "Greenhouse 2"), "greenhouse-2")
        XCTAssertEqual(ServerConfig.slug(from: "  Nan's Back Garden!  "), "nan-s-back-garden")
        XCTAssertEqual(ServerConfig.slug(from: "greenhouse-2"), "greenhouse-2")
    }

    func testSlugFallsBackToDefaultWhenNameHasNothingToSlugify() {
        XCTAssertEqual(ServerConfig.slug(from: ""), ServerConfig.mapSlug)
        XCTAssertEqual(ServerConfig.slug(from: "   "), ServerConfig.mapSlug)
        XCTAssertEqual(ServerConfig.slug(from: "!!!"), ServerConfig.mapSlug)
    }

    // MARK: Local version record

    func testLocalVersionWrittenBeforeMapsWereNamedBelongsToTheDefaultMap() throws {
        let legacy = Data(#"{"version":2,"source":"ios","updatedAt":770000000}"#.utf8)
        let record = try JSONDecoder().decode(LocalMapVersion.self, from: legacy)
        XCTAssertEqual(record.slug, ServerConfig.mapSlug)
        XCTAssertEqual(record.version, 2)
    }

    func testLocalVersionRoundTripsItsSlug() throws {
        let record = LocalMapVersion(version: 7, source: .ios, updatedAt: Date(timeIntervalSince1970: 100), slug: "home")
        let decoded = try JSONDecoder().decode(LocalMapVersion.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.slug, "home")
    }


    func testMapStorePersistsVersionRecordAndPointCloud() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = MapStore(directory: dir)

        XCTAssertNil(store.loadVersion())
        try store.saveVersion(LocalMapVersion(version: 4, source: .web, updatedAt: Date(timeIntervalSince1970: 100), slug: "home"))
        XCTAssertEqual(store.loadVersion()?.version, 4)
        XCTAssertEqual(store.loadVersion()?.slug, "home")

        try store.savePointCloud(PointCloudCodec.encode([SIMD3<Float>(0, 0, 0)]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.pointCloudURL.path))

        try store.deleteAll()
        XCTAssertNil(store.loadVersion())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pointCloudURL.path))
    }
}
