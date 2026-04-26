//
//  SessionStructureCodableTests.swift
//  DromosTests
//
//  Unit tests for SessionStructure, StructureSegment, Target, Constraint, and User
//  Codable round-trips (DRO-218 / DRO-213 Phase 4).
//
//  NOTE: This file requires a DromosTests test target in the Xcode project.
//  Tests are written against the shape produced by materialize-structure.ts.
//

import XCTest
@testable import Dromos

// MARK: - Helpers

/// JSONDecoder with explicit snake_case → camelCase conversion.
/// Used in tests because we decode raw JSON literals (not via Supabase PostgREST).
private let testDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}()

/// JSONEncoder with snake_case output, matching the DB schema.
private let testEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.keyEncodingStrategy = .convertToSnakeCase
    return e
}()

// MARK: - Target Codable Tests

final class TargetCodableTests: XCTestCase {

    // MARK: - Single-value targets

    func test_ftpPct_value_roundtrip() throws {
        let json = #"{"type":"ftp_pct","value":95}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .ftpPct(value: 95, min: nil, max: nil))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_ftpPct_range_roundtrip() throws {
        let json = #"{"type":"ftp_pct","min":88,"max":95}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .ftpPct(value: nil, min: 88, max: 95))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_vmaPct_value_roundtrip() throws {
        let json = #"{"type":"vma_pct","value":85}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .vmaPct(value: 85, min: nil, max: nil))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_vmaPct_range_roundtrip() throws {
        let json = #"{"type":"vma_pct","min":80,"max":90}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .vmaPct(value: nil, min: 80, max: 90))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_cssPct_value_roundtrip() throws {
        let json = #"{"type":"css_pct","value":100}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .cssPct(value: 100, min: nil, max: nil))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_cssPct_range_roundtrip() throws {
        let json = #"{"type":"css_pct","min":95,"max":105}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .cssPct(value: nil, min: 95, max: 105))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_rpe_roundtrip() throws {
        let json = #"{"type":"rpe","value":6}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .rpe(value: 6))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_hrZone_roundtrip() throws {
        let json = #"{"type":"hr_zone","value":3}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .hrZone(value: 3))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_hrPctMax_value_roundtrip() throws {
        let json = #"{"type":"hr_pct_max","value":78}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .hrPctMax(value: 78, min: nil, max: nil))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_hrPctMax_range_roundtrip() throws {
        let json = #"{"type":"hr_pct_max","min":70,"max":80}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .hrPctMax(value: nil, min: 70, max: 80))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_powerWatts_value_roundtrip() throws {
        let json = #"{"type":"power_watts","value":260}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .powerWatts(value: 260, min: nil, max: nil))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_powerWatts_range_roundtrip() throws {
        let json = #"{"type":"power_watts","min":240,"max":270}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .powerWatts(value: nil, min: 240, max: 270))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_pacePerKm_roundtrip() throws {
        let json = #"{"type":"pace_per_km","value":"5:30"}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .pacePerKm(value: "5:30"))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_pacePerHundredM_roundtrip() throws {
        let json = #"{"type":"pace_per_100m","value":"1:50"}"#
        let target = try JSONDecoder().decode(Target.self, from: Data(json.utf8))
        XCTAssertEqual(target, .pacePerHundredM(value: "1:50"))

        let encoded = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(Target.self, from: encoded)
        XCTAssertEqual(decoded, target)
    }

    func test_unknownType_throws() throws {
        let json = #"{"type":"unknown_metric","value":42}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Target.self, from: Data(json.utf8)))
    }
}

// MARK: - Constraint Codable Tests

final class ConstraintCodableTests: XCTestCase {

    func test_hrMax_roundtrip() throws {
        let json = #"{"type":"hr_max","value":145}"#
        let constraint = try JSONDecoder().decode(Constraint.self, from: Data(json.utf8))
        XCTAssertEqual(constraint, .hrMax(value: 145))

        let encoded = try JSONEncoder().encode(constraint)
        let decoded = try JSONDecoder().decode(Constraint.self, from: encoded)
        XCTAssertEqual(decoded, constraint)
    }

    func test_unknownType_throws() throws {
        let json = #"{"type":"cadence_max","value":90}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Constraint.self, from: Data(json.utf8)))
    }
}

// MARK: - StructureSegment Codable Tests

final class StructureSegmentCodableTests: XCTestCase {

    func test_leafSegment_roundtrip() throws {
        let json = """
        {
          "label": "work",
          "duration_minutes": 10.0,
          "target": {"type": "ftp_pct", "value": 95},
          "cadence_rpm": 90,
          "cue": "steady power"
        }
        """
        let seg = try testDecoder.decode(StructureSegment.self, from: Data(json.utf8))
        XCTAssertEqual(seg.label, "work")
        XCTAssertEqual(seg.durationMinutes, 10.0)
        XCTAssertEqual(seg.target, .ftpPct(value: 95, min: nil, max: nil))
        XCTAssertEqual(seg.cadenceRpm, 90)
        XCTAssertEqual(seg.cue, "steady power")

        let encoded = try testEncoder.encode(seg)
        let decoded = try testDecoder.decode(StructureSegment.self, from: encoded)
        XCTAssertEqual(decoded, seg)
    }

    func test_repeatSegment_withRestSeconds() throws {
        let json = """
        {
          "label": "repeat",
          "repeats": 5,
          "rest_seconds": 30,
          "segments": [
            {
              "label": "work",
              "distance_meters": 400,
              "target": {"type": "vma_pct", "value": 100}
            }
          ]
        }
        """
        let seg = try testDecoder.decode(StructureSegment.self, from: Data(json.utf8))
        XCTAssertEqual(seg.label, "repeat")
        XCTAssertEqual(seg.repeats, 5)
        XCTAssertEqual(seg.restSeconds, 30)
        XCTAssertEqual(seg.segments?.count, 1)
        XCTAssertEqual(seg.segments?.first?.label, "work")
        XCTAssertEqual(seg.segments?.first?.distanceMeters, 400)
        XCTAssertEqual(seg.segments?.first?.target, .vmaPct(value: 100, min: nil, max: nil))
    }

    func test_repeatSegment_withRecovery() throws {
        let json = """
        {
          "label": "repeat",
          "repeats": 4,
          "recovery": {
            "label": "recovery",
            "duration_minutes": 2.0,
            "target": {"type": "rpe", "value": 3}
          },
          "segments": [
            {
              "label": "work",
              "duration_minutes": 5.0,
              "target": {"type": "ftp_pct", "min": 88, "max": 95}
            }
          ]
        }
        """
        let seg = try testDecoder.decode(StructureSegment.self, from: Data(json.utf8))
        XCTAssertEqual(seg.repeats, 4)
        XCTAssertEqual(seg.recovery?.label, "recovery")
        XCTAssertEqual(seg.recovery?.durationMinutes, 2.0)
        XCTAssertEqual(seg.recovery?.target, .rpe(value: 3))
        XCTAssertEqual(seg.segments?.first?.target, .ftpPct(value: nil, min: 88, max: 95))
    }

    func test_drillSegment_noTarget() throws {
        let json = """
        {
          "label": "drill",
          "distance_meters": 100,
          "drill": "pull"
        }
        """
        let seg = try testDecoder.decode(StructureSegment.self, from: Data(json.utf8))
        XCTAssertEqual(seg.label, "drill")
        XCTAssertEqual(seg.distanceMeters, 100)
        XCTAssertEqual(seg.drill, "pull")
        XCTAssertNil(seg.target)
    }

    func test_segmentWithConstraints() throws {
        let json = """
        {
          "label": "work",
          "duration_minutes": 20.0,
          "target": {"type": "hr_zone", "value": 4},
          "constraints": [{"type": "hr_max", "value": 145}]
        }
        """
        let seg = try testDecoder.decode(StructureSegment.self, from: Data(json.utf8))
        XCTAssertEqual(seg.target, .hrZone(value: 4))
        XCTAssertEqual(seg.constraints?.count, 1)
        XCTAssertEqual(seg.constraints?.first, .hrMax(value: 145))
    }
}

// MARK: - SessionStructure Full Round-trip Tests

final class SessionStructureTests: XCTestCase {

    func test_simpleSession_roundtrip() throws {
        let json = """
        {
          "segments": [
            {
              "label": "warmup",
              "duration_minutes": 10.0,
              "target": {"type": "rpe", "value": 4}
            },
            {
              "label": "work",
              "duration_minutes": 30.0,
              "target": {"type": "ftp_pct", "value": 88}
            },
            {
              "label": "cooldown",
              "duration_minutes": 5.0,
              "target": {"type": "rpe", "value": 3}
            }
          ]
        }
        """
        let structure = try testDecoder.decode(SessionStructure.self, from: Data(json.utf8))
        XCTAssertEqual(structure.segments.count, 3)
        XCTAssertEqual(structure.segments[0].label, "warmup")
        XCTAssertEqual(structure.segments[1].label, "work")
        XCTAssertEqual(structure.segments[2].label, "cooldown")

        let encoded = try testEncoder.encode(structure)
        let decoded = try testDecoder.decode(SessionStructure.self, from: encoded)
        XCTAssertEqual(decoded, structure)
    }

    /// Mirrors the SWIM_Tempo_02 fixture: 3-level nesting (session → repeat → work/recovery)
    func test_nestedRepeat_3levels_roundtrip() throws {
        let json = """
        {
          "segments": [
            {
              "label": "warmup",
              "distance_meters": 300,
              "target": {"type": "rpe", "value": 3}
            },
            {
              "label": "repeat",
              "repeats": 4,
              "rest_seconds": 30,
              "segments": [
                {
                  "label": "work",
                  "distance_meters": 100,
                  "target": {"type": "css_pct", "value": 100}
                },
                {
                  "label": "drill",
                  "distance_meters": 50,
                  "drill": "kick"
                }
              ]
            },
            {
              "label": "repeat",
              "repeats": 2,
              "recovery": {
                "label": "recovery",
                "distance_meters": 50,
                "target": {"type": "rpe", "value": 3}
              },
              "segments": [
                {
                  "label": "work",
                  "distance_meters": 200,
                  "target": {"type": "css_pct", "min": 95, "max": 105}
                }
              ]
            },
            {
              "label": "cooldown",
              "distance_meters": 200,
              "target": {"type": "rpe", "value": 2}
            }
          ]
        }
        """
        let structure = try testDecoder.decode(SessionStructure.self, from: Data(json.utf8))
        XCTAssertEqual(structure.segments.count, 4)

        // First repeat block
        let repeat1 = structure.segments[1]
        XCTAssertEqual(repeat1.label, "repeat")
        XCTAssertEqual(repeat1.repeats, 4)
        XCTAssertEqual(repeat1.restSeconds, 30)
        XCTAssertEqual(repeat1.segments?.count, 2)
        XCTAssertEqual(repeat1.segments?.first?.target, .cssPct(value: 100, min: nil, max: nil))

        // Second repeat block with recovery
        let repeat2 = structure.segments[2]
        XCTAssertEqual(repeat2.repeats, 2)
        XCTAssertNotNil(repeat2.recovery)
        XCTAssertEqual(repeat2.recovery?.label, "recovery")
        XCTAssertEqual(repeat2.segments?.first?.target, .cssPct(value: nil, min: 95, max: 105))

        // Round-trip
        let encoded = try testEncoder.encode(structure)
        let decoded = try testDecoder.decode(SessionStructure.self, from: encoded)
        XCTAssertEqual(decoded, structure)
    }

    func test_runIntervalSession_vmaPct() throws {
        let json = """
        {
          "segments": [
            {
              "label": "warmup",
              "duration_minutes": 15.0,
              "target": {"type": "rpe", "value": 4}
            },
            {
              "label": "repeat",
              "repeats": 6,
              "rest_seconds": 60,
              "segments": [
                {
                  "label": "work",
                  "distance_meters": 400,
                  "target": {"type": "vma_pct", "value": 100}
                }
              ]
            },
            {
              "label": "cooldown",
              "duration_minutes": 10.0,
              "target": {"type": "rpe", "value": 3}
            }
          ]
        }
        """
        let structure = try testDecoder.decode(SessionStructure.self, from: Data(json.utf8))
        let repeatBlock = structure.segments[1]
        XCTAssertEqual(repeatBlock.segments?.first?.target, .vmaPct(value: 100, min: nil, max: nil))

        let encoded = try testEncoder.encode(structure)
        let decoded = try testDecoder.decode(SessionStructure.self, from: encoded)
        XCTAssertEqual(decoded, structure)
    }
}

// MARK: - User maxHr / birthYear Tests

final class UserCodableTests: XCTestCase {

    func test_user_withMaxHrAndBirthYear() throws {
        // Simulates the JSON that Supabase returns for a user with the new columns.
        // Uses snake_case keys as the DB returns them; testDecoder converts to camelCase.
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "email": "test@example.com",
          "name": "Test Athlete",
          "race_objective": null,
          "race_date": null,
          "time_objective_minutes": null,
          "vma": 17.5,
          "css_seconds_per100m": 95,
          "ftp": 240,
          "experience_years": 3,
          "current_weekly_hours": 10.0,
          "swim_days": null,
          "bike_days": null,
          "run_days": null,
          "mon_duration": null,
          "tue_duration": null,
          "wed_duration": null,
          "thu_duration": null,
          "fri_duration": null,
          "sat_duration": null,
          "sun_duration": null,
          "max_hr": 185,
          "birth_year": 1988,
          "onboarding_completed": true,
          "strava_athlete_id": null,
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-04-25T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let user = try decoder.decode(User.self, from: Data(json.utf8))
        XCTAssertEqual(user.maxHr, 185)
        XCTAssertEqual(user.birthYear, 1988)
        XCTAssertEqual(user.vma, 17.5)
    }

    func test_user_nullMaxHrAndBirthYear() throws {
        // Existing users before Phase 6 onboarding — max_hr and birth_year are NULL.
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "email": "legacy@example.com",
          "name": null,
          "race_objective": null,
          "race_date": null,
          "time_objective_minutes": null,
          "vma": null,
          "css_seconds_per100m": null,
          "ftp": null,
          "experience_years": null,
          "current_weekly_hours": null,
          "swim_days": null,
          "bike_days": null,
          "run_days": null,
          "mon_duration": null,
          "tue_duration": null,
          "wed_duration": null,
          "thu_duration": null,
          "fri_duration": null,
          "sat_duration": null,
          "sun_duration": null,
          "max_hr": null,
          "birth_year": null,
          "onboarding_completed": false,
          "strava_athlete_id": null,
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-04-25T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let user = try decoder.decode(User.self, from: Data(json.utf8))
        XCTAssertNil(user.maxHr)
        XCTAssertNil(user.birthYear)
    }
}
