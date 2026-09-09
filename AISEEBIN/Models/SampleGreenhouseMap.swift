import Foundation

/// Sample layout for a small botanic greenhouse.
///
/// The origin (0, 0) is the Main Entrance, which is also where the operator
/// should stand when the `ARWorldMap` is first scanned so that the graph and the
/// world map share a frame. The corridor runs "into" the building along -Z.
///
/// ```
///            z = -14        [Orchid Display]
///                               |
///            z =  -8  [Tropical House]---[Central Junction]---[Palm Conservatory]
///                                             |                     |
///            z =  -2                          |                 [Restrooms]
///                                             |                /
///            z =   0                    [Main Entrance]-------
///                         x = -6            x = 0            x = +6
/// ```
enum SampleGreenhouseMap {
    static let map = NavigationMap(
        name: "Sample Greenhouse",
        pois: [
            NavigationPOI(id: "entrance",  name: "Main Entrance",     x:  0, z:   0),
            NavigationPOI(id: "junction",  name: "Central Junction",  x:  0, z:  -8, category: .junction),
            NavigationPOI(id: "tropical",  name: "Tropical House",    x: -6, z:  -8),
            NavigationPOI(id: "orchid",    name: "Orchid Display",    x: -6, z: -14),
            NavigationPOI(id: "palm",      name: "Palm Conservatory", x:  6, z:  -8),
            NavigationPOI(id: "restrooms", name: "Restrooms",         x:  6, z:  -2),
        ],
        edges: [
            NavigationEdge(from: "entrance",  to: "junction"),
            NavigationEdge(from: "junction",  to: "tropical"),
            NavigationEdge(from: "tropical",  to: "orchid"),
            NavigationEdge(from: "junction",  to: "palm"),
            NavigationEdge(from: "palm",      to: "restrooms"),
            NavigationEdge(from: "restrooms", to: "entrance"),
        ]
    )
}
