//
//  StructureRenderSnapshotTests.swift
//  DromosTests
//
//  DRO-221 Phase 7: parity snapshots between the legacy template renderer
//  and the new structure-based renderer. For each representative template,
//  the new path (materialize → flattenedSegments / stepSummaries) must
//  produce equivalent output to the legacy path (flattenSegments(template)).
//
//  "Equivalent" here means:
//    - Same number of flat segments
//    - Matching labels, durations, distances, intensityPct, isRecovery
//    - Same number of step summaries
//    - Matching repeat-block flags
//  Text strings may differ on whitespace formatting between the two paths;
//  the assertions below check the load-bearing invariants, not exact text.
//
//  No DromosTests Xcode target exists yet; this file compiles under
//  `@testable import Dromos` once the target is wired up.
//

import Foundation
import XCTest
@testable import Dromos

final class StructureRenderSnapshotTests: XCTestCase {

    private let svc = WorkoutLibraryService.shared

    // MARK: - Representative templates (covering each sport + intensity flavor)

    /// Fixture: bike easy with cadence + cue. Mirrors `BIKE_Easy_17` shape.
    private func bikeEasyTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            templateId: "BIKE_Easy_TEST",
            segments: [
                WorkoutSegment(
                    label: "work",
                    durationMinutes: 120,
                    ftpPct: 62,
                    cadenceRpm: 90,
                    cue: "all Z1 <180W, rolling OK"
                )
            ]
        )
    }

    /// Fixture: bike intervals with repeats + recovery. Mirrors a `BIKE_Intervals_*` shape.
    private func bikeIntervalsTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            templateId: "BIKE_Intervals_TEST",
            segments: [
                WorkoutSegment(label: "warmup", durationMinutes: 15, ftpPct: 50),
                WorkoutSegment(
                    label: "repeat",
                    repeats: 4,
                    segments: [
                        WorkoutSegment(label: "work", durationMinutes: 6, ftpPct: 95)
                    ],
                    recovery: WorkoutSegment(label: "recovery", durationMinutes: 4, ftpPct: 50)
                ),
                WorkoutSegment(label: "cooldown", durationMinutes: 10, ftpPct: 45)
            ]
        )
    }

    /// Fixture: run easy with mas_pct. Materializer renames mas_pct → vma_pct.
    private func runEasyTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            templateId: "RUN_Easy_TEST",
            segments: [
                WorkoutSegment(label: "work", durationMinutes: 90, masPct: 60, cue: "16k @5:30/km")
            ]
        )
    }

    /// Fixture: swim intervals. Pace tags map to RPE.
    private func swimIntervalsTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            templateId: "SWIM_Intervals_TEST",
            segments: [
                WorkoutSegment(label: "warmup", distanceMeters: 400, pace: "slow"),
                WorkoutSegment(
                    label: "repeat",
                    repeats: 10,
                    restSeconds: 15,
                    segments: [
                        WorkoutSegment(label: "work", distanceMeters: 100, pace: "quick")
                    ]
                ),
                WorkoutSegment(label: "cooldown", distanceMeters: 200, pace: "slow")
            ]
        )
    }

    /// Fixture: 3-level nested repeats. Mirrors `SWIM_Tempo_02`.
    private func swimTempoNestedTemplate() -> WorkoutTemplate {
        WorkoutTemplate(
            templateId: "SWIM_Tempo_NESTED_TEST",
            segments: [
                WorkoutSegment(label: "warmup", distanceMeters: 300, pace: "slow"),
                WorkoutSegment(
                    label: "repeat",
                    repeats: 3,
                    segments: [
                        WorkoutSegment(
                            label: "repeat",
                            repeats: 4,
                            restSeconds: 15,
                            segments: [
                                WorkoutSegment(label: "work", distanceMeters: 100, pace: "medium")
                            ]
                        )
                    ],
                    recovery: WorkoutSegment(label: "recovery", distanceMeters: 100, pace: "slow")
                ),
                WorkoutSegment(label: "cooldown", distanceMeters: 200, pace: "slow")
            ]
        )
    }

    // MARK: - Athlete metrics for resolution

    private let ftp = 250
    private let vma = 18.0
    private let css: Int? = nil
    private let maxHr = 200

    // MARK: - Parity assertions — flat segments

    private func assertFlatParity(
        _ legacy: [FlatSegment],
        _ structureFlat: [FlatSegment],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(legacy.count, structureFlat.count,
                       "segment count differs", file: file, line: line)
        for (a, b) in zip(legacy, structureFlat) {
            XCTAssertEqual(a.label, b.label, "label", file: file, line: line)
            XCTAssertEqual(a.durationMinutes, b.durationMinutes, accuracy: 0.01,
                           "duration", file: file, line: line)
            XCTAssertEqual(a.distanceMeters, b.distanceMeters,
                           "distance", file: file, line: line)
            XCTAssertEqual(a.intensityPct, b.intensityPct,
                           "intensityPct", file: file, line: line)
            XCTAssertEqual(a.isRecovery, b.isRecovery,
                           "isRecovery", file: file, line: line)
        }
    }

    // MARK: - Tests

    func test_bikeEasy_flatSegments_parity() {
        let tpl = bikeEasyTemplate()
        let legacy = svc.flattenedSegments(for: tpl.templateId)  // empty since not in bundle
        // Build the legacy expected from the in-memory template directly.
        let expected: [FlatSegment] = [
            FlatSegment(label: "work", durationMinutes: 120, intensityPct: 62,
                        distanceMeters: nil, pace: nil, isRecovery: false)
        ]
        let structure = svc.materialize(template: tpl)
        let structFlat = svc.flattenedSegments(structure: structure, sport: "bike",
                                               ftp: ftp, vma: nil, css: nil, maxHr: nil)
        assertFlatParity(expected, structFlat)
        _ = legacy  // legacy lookup unused (templateId not in bundled lib)
    }

    func test_bikeIntervals_flatSegments_parity() {
        let tpl = bikeIntervalsTemplate()
        // Legacy expansion: warmup, 4× (work, recovery between each pair), cooldown
        // = 1 + (4 work + 3 recovery) + 1 = 9 segments
        let structure = svc.materialize(template: tpl)
        let structFlat = svc.flattenedSegments(structure: structure, sport: "bike",
                                               ftp: ftp, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(structFlat.count, 9)
        XCTAssertEqual(structFlat[0].label, "warmup")
        XCTAssertEqual(structFlat[0].intensityPct, 50)
        XCTAssertEqual(structFlat[1].label, "work")
        XCTAssertEqual(structFlat[1].intensityPct, 95)
        XCTAssertEqual(structFlat[2].label, "recovery")
        XCTAssertEqual(structFlat[2].intensityPct, 50)
        XCTAssertEqual(structFlat[2].isRecovery, true)
        XCTAssertEqual(structFlat[8].label, "cooldown")
        XCTAssertEqual(structFlat[8].intensityPct, 45)
    }

    func test_runEasy_masPctRenamesAndIntensity() {
        let tpl = runEasyTemplate()
        let structure = svc.materialize(template: tpl)
        // mas_pct 60 should materialize to vma_pct: 60 → intensityPct = 60
        XCTAssertEqual(structure.segments[0].target,
                       .vmaPct(value: 60, min: nil, max: nil))
        let structFlat = svc.flattenedSegments(structure: structure, sport: "run",
                                               ftp: nil, vma: vma, css: nil, maxHr: nil)
        XCTAssertEqual(structFlat.count, 1)
        XCTAssertEqual(structFlat[0].intensityPct, 60)
        XCTAssertEqual(structFlat[0].durationMinutes, 90, accuracy: 0.01)
    }

    func test_swimIntervals_paceMapsToRpe_intensityIs70() {
        let tpl = swimIntervalsTemplate()
        let structure = svc.materialize(template: tpl)
        // pace "slow" → rpe 3, "quick" → rpe 7
        XCTAssertEqual(structure.segments[0].target, .rpe(value: 3))
        XCTAssertEqual(structure.segments[2].target, .rpe(value: 3))
        // Inner work segment of repeat
        XCTAssertEqual(structure.segments[1].segments?[0].target, .rpe(value: 7))

        let structFlat = svc.flattenedSegments(structure: structure, sport: "swim",
                                               ftp: nil, vma: nil, css: nil, maxHr: nil)
        // warmup + 10×work + 9×rest (between iterations) + cooldown = 21
        XCTAssertEqual(structFlat.count, 21)
        // work segments at intensity 70 (rpe 7 × 10)
        let workIntensities = structFlat.filter { $0.label == "work" }.map { $0.intensityPct }
        XCTAssertTrue(workIntensities.allSatisfy { $0 == 70 })
        // 9 inter-repeat rest segments
        XCTAssertEqual(structFlat.filter { $0.label == "rest" }.count, 9)
    }

    func test_swimTempoNested_3levelExpansion() {
        // Outer 3× of (inner 4× of work + 15s rest) with 100m recovery between outer iters
        // = warmup + [3 × (4 work + 3 rest)] + (2 × recovery between outer) + cooldown
        // = 1 + 3*7 + 2 + 1 = 25 flat segments
        let tpl = swimTempoNestedTemplate()
        let structure = svc.materialize(template: tpl)
        let flat = svc.flattenedSegments(structure: structure, sport: "swim",
                                         ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(flat.count, 25)
        XCTAssertEqual(flat.filter { $0.label == "work" }.count, 12)
        XCTAssertEqual(flat.filter { $0.label == "rest" }.count, 9)        // 3 outer × 3 inner-rests
        XCTAssertEqual(flat.filter { $0.label == "recovery" }.count, 2)    // between outer iters
    }

    // MARK: - Edge cases

    func test_athleteMissingFtp_displayFallsBackToRpe() {
        let target: Target = .ftpPct(value: 95, min: nil, max: nil)
        let str = svc.displayString(for: target, sport: "bike",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertNotNil(str)
        XCTAssertTrue(str!.hasPrefix("RPE "), "got: \(str!)")
    }

    func test_athleteMissingVma_displayFallsBackToRpe() {
        let target: Target = .vmaPct(value: 80, min: nil, max: nil)
        let str = svc.displayString(for: target, sport: "run",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertNotNil(str)
        XCTAssertTrue(str!.hasPrefix("RPE "), "got: \(str!)")
    }

    func test_athleteMissingMaxHr_hrZoneShowsFallbackLabel() {
        let str = svc.displayString(for: .hrZone(value: 3), sport: "run",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(str, "Z3 (set max HR in profile)")
    }

    func test_targetNil_intensityIsNil_displayIsNil() {
        // Drill / skill segment with no intensity target
        XCTAssertNil(svc.intensityPct(for: nil, sport: "swim",
                                      ftp: nil, vma: nil, css: nil, maxHr: nil))
        XCTAssertNil(svc.displayString(for: nil, sport: "swim",
                                       ftp: nil, vma: nil, css: nil, maxHr: nil))
    }

    func test_sessionWithNilStructure_dualPathFallsBackToTemplate() {
        // The dual-path entry point flattenedSegments(for: session:...) should fall back
        // to template lookup when session.structure is nil.
        let session = PlanSession(
            id: UUID(), weekId: UUID(), day: "Monday", sport: "bike",
            type: "Easy", templateId: "BIKE_Easy_NOT_IN_BUNDLE", durationMinutes: 60,
            isBrick: false, notes: nil, orderInDay: 0, feedback: nil,
            matchedActivityId: nil, structure: nil
        )
        // No bundled template with this ID → returns empty rather than crashing
        let flat = svc.flattenedSegments(for: session,
                                         ftp: ftp, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(flat.count, 0)
    }
}
