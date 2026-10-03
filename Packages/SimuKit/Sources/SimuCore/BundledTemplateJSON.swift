import Foundation

/// Compiled copies of `Fixtures/templates/*.json`.
/// The sandboxed Mac app cannot open the repository path, and Xcode currently
/// builds SimuCore without a resource bundle (`SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE`).
enum BundledTemplateJSON {
    static func data(named name: String) -> Data? {
        switch name {
        case "office":
            return Data(office.utf8)
        case "classroom":
            return Data(classroom.utf8)
        default:
            return nil
        }
    }

    private static let office = #"""
{
  "overridable": [
    "hvac.setpointC",
    "hvac.supply",
    "hvac.returnTerminal",
    "occupancy.occupantCount"
  ],
  "lockedAssumptions": [
    "omitted: envelope_u_value",
    "omitted: weather_file",
    "omitted: furniture_boxes"
  ],
  "project": {
    "schemaVersion": 2,
    "id": "22222222-2222-2222-2222-222222222222",
    "name": "办公室",
    "spaceType": "office",
    "lengthUnit": "m",
    "coordinateSystem": "rightHandedZUp",
    "geometry": {
      "sizeX": { "value": 6.0, "unit": "m", "source": "preset" },
      "sizeY": { "value": 6.0, "unit": "m", "source": "preset" },
      "sizeZ": { "value": 2.8, "unit": "m", "source": "preset" },
      "northYawDegrees": { "value": 0.0, "unit": "deg", "source": "assumed" },
      "openings": [
        {
          "id": "W1",
          "kind": "window",
          "wall": "xMax",
          "s0": { "value": 2.25, "unit": "m", "source": "preset" },
          "s1": { "value": 3.75, "unit": "m", "source": "preset" },
          "z0": { "value": 0.9, "unit": "m", "source": "preset" },
          "z1": { "value": 2.2, "unit": "m", "source": "preset" },
          "heatFluxWm2": { "value": 80.0, "unit": "W/m2", "source": "preset" }
        }
      ],
      "obstacles": [],
      "assumptions": [
        "omitted: furniture_boxes",
        "omitted: envelope_u_value",
        "omitted: weather_file"
      ]
    },
    "occupancy": {
      "occupantCount": { "value": 8, "unit": "1", "source": "preset" },
      "occupantSensibleW": { "value": 70.0, "unit": "W", "source": "preset" },
      "lightingW": { "value": 180.0, "unit": "W", "source": "preset" },
      "equipmentW": { "value": 400.0, "unit": "W", "source": "preset" },
      "seats": [
        { "id": "S1", "position": { "x": 1.5, "y": 1.5, "z": 1.1 }, "source": "preset" },
        { "id": "S2", "position": { "x": 1.5, "y": 4.5, "z": 1.1 }, "source": "preset" },
        { "id": "S3", "position": { "x": 4.5, "y": 1.5, "z": 1.1 }, "source": "preset" },
        { "id": "S4", "position": { "x": 4.5, "y": 4.5, "z": 1.1 }, "source": "preset" }
      ]
    },
    "hvac": {
      "kind": "splitAC",
      "setpointC": { "value": 26.0, "unit": "C", "source": "user" },
      "supplyTemperatureC": { "value": 16.0, "unit": "C", "source": "preset" },
      "supplySpeedMs": { "value": 1.2, "unit": "m/s", "source": "preset" },
      "supplyAirflowM3s": { "value": 0.108, "unit": "m3/s", "source": "preset" },
      "supply": {
        "id": "SUP1",
        "wall": "xMin",
        "s0": { "value": 2.75, "unit": "m", "source": "preset" },
        "s1": { "value": 3.25, "unit": "m", "source": "preset" },
        "z0": { "value": 2.48, "unit": "m", "source": "preset" },
        "z1": { "value": 2.66, "unit": "m", "source": "preset" }
      },
      "returnTerminal": {
        "id": "RET1",
        "wall": "xMin",
        "s0": { "value": 2.7, "unit": "m", "source": "preset" },
        "s1": { "value": 3.3, "unit": "m", "source": "preset" },
        "z0": { "value": 1.85, "unit": "m", "source": "preset" },
        "z1": { "value": 2.05, "unit": "m", "source": "preset" }
      },
      "outdoorAirM3s": { "value": 0.02, "unit": "m3/s", "source": "assumed" },
      "cop": { "value": 3.0, "unit": "1", "source": "assumed" }
    }
  }
}
"""#

    private static let classroom = #"""
{
  "overridable": [
    "hvac.setpointC",
    "hvac.supply",
    "hvac.returnTerminal",
    "occupancy.occupantCount"
  ],
  "lockedAssumptions": [
    "omitted: envelope_u_value",
    "omitted: weather_file",
    "omitted: furniture_boxes"
  ],
  "project": {
    "schemaVersion": 2,
    "id": "33333333-3333-3333-3333-333333333333",
    "name": "教室",
    "spaceType": "classroom",
    "lengthUnit": "m",
    "coordinateSystem": "rightHandedZUp",
    "geometry": {
      "sizeX": { "value": 8.0, "unit": "m", "source": "preset" },
      "sizeY": { "value": 6.0, "unit": "m", "source": "preset" },
      "sizeZ": { "value": 3.0, "unit": "m", "source": "preset" },
      "northYawDegrees": { "value": 0.0, "unit": "deg", "source": "assumed" },
      "openings": [
        {
          "id": "W1",
          "kind": "window",
          "wall": "xMax",
          "s0": { "value": 1.5, "unit": "m", "source": "preset" },
          "s1": { "value": 3.5, "unit": "m", "source": "preset" },
          "z0": { "value": 0.9, "unit": "m", "source": "preset" },
          "z1": { "value": 2.4, "unit": "m", "source": "preset" },
          "heatFluxWm2": { "value": 80.0, "unit": "W/m2", "source": "preset" }
        }
      ],
      "obstacles": [],
      "assumptions": [
        "omitted: furniture_boxes",
        "omitted: envelope_u_value",
        "omitted: weather_file"
      ]
    },
    "occupancy": {
      "occupantCount": { "value": 24, "unit": "1", "source": "preset" },
      "occupantSensibleW": { "value": 70.0, "unit": "W", "source": "preset" },
      "lightingW": { "value": 480.0, "unit": "W", "source": "preset" },
      "equipmentW": { "value": 600.0, "unit": "W", "source": "preset" },
      "seats": [
        { "id": "S1", "position": { "x": 2.0, "y": 1.2, "z": 1.1 }, "source": "preset" },
        { "id": "S2", "position": { "x": 2.0, "y": 2.4, "z": 1.1 }, "source": "preset" },
        { "id": "S3", "position": { "x": 2.0, "y": 3.6, "z": 1.1 }, "source": "preset" },
        { "id": "S4", "position": { "x": 2.0, "y": 4.8, "z": 1.1 }, "source": "preset" },
        { "id": "S5", "position": { "x": 4.0, "y": 1.2, "z": 1.1 }, "source": "preset" },
        { "id": "S6", "position": { "x": 4.0, "y": 2.4, "z": 1.1 }, "source": "preset" },
        { "id": "S7", "position": { "x": 4.0, "y": 3.6, "z": 1.1 }, "source": "preset" },
        { "id": "S8", "position": { "x": 4.0, "y": 4.8, "z": 1.1 }, "source": "preset" },
        { "id": "S9", "position": { "x": 6.0, "y": 1.2, "z": 1.1 }, "source": "preset" },
        { "id": "S10", "position": { "x": 6.0, "y": 2.4, "z": 1.1 }, "source": "preset" },
        { "id": "S11", "position": { "x": 6.0, "y": 3.6, "z": 1.1 }, "source": "preset" },
        { "id": "S12", "position": { "x": 6.0, "y": 4.8, "z": 1.1 }, "source": "preset" }
      ]
    },
    "hvac": {
      "kind": "splitAC",
      "setpointC": { "value": 26.0, "unit": "C", "source": "user" },
      "supplyTemperatureC": { "value": 16.0, "unit": "C", "source": "preset" },
      "supplySpeedMs": { "value": 1.2, "unit": "m/s", "source": "preset" },
      "supplyAirflowM3s": { "value": 0.108, "unit": "m3/s", "source": "preset" },
      "supply": {
        "id": "SUP1",
        "wall": "xMin",
        "s0": { "value": 2.75, "unit": "m", "source": "preset" },
        "s1": { "value": 3.25, "unit": "m", "source": "preset" },
        "z0": { "value": 2.68, "unit": "m", "source": "preset" },
        "z1": { "value": 2.86, "unit": "m", "source": "preset" }
      },
      "returnTerminal": {
        "id": "RET1",
        "wall": "xMin",
        "s0": { "value": 2.7, "unit": "m", "source": "preset" },
        "s1": { "value": 3.3, "unit": "m", "source": "preset" },
        "z0": { "value": 1.85, "unit": "m", "source": "preset" },
        "z1": { "value": 2.05, "unit": "m", "source": "preset" }
      },
      "outdoorAirM3s": { "value": 0.05, "unit": "m3/s", "source": "assumed" },
      "cop": { "value": 3.0, "unit": "1", "source": "assumed" }
    }
  }
}
"""#
}
