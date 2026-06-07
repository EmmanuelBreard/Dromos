//
//  StructureRenderTests.swift
//  DromosTests
//
//  DRO-219 Phase 5: tests for the polymorphic Target formatter, structure-based
//  flatten/summarize, and the Swift materialize(template:) port.
//
//  Note: there is no DromosTests Xcode target yet (Phase 7 setup). This file
//  compiles as Swift but tests cannot be executed until the test target is added.
//

import Foundation
import XCTest
@testable import Dromos

final class StructureRenderTests: XCTestCase {

    private let svc = WorkoutLibraryService.shared

    // MARK: - displayString — never raw %

    func test_displayString_ftpPct_resolvesToWatts() {
        let t: Target = .ftpPct(value: nil, min: 95, max: 100)
        let out = svc.displayString(for: t, sport: "bike", ftp: 275, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "261–275 W")
    }

    func test_displayString_ftpPct_singleValue() {
        let t: Target = .ftpPct(value: 80, min: nil, max: nil)
        let out = svc.displayString(for: t, sport: "bike", ftp: 250, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "200 W")
    }

    func test_displayString_ftpPct_fallsBackToRpeWhenFtpMissing() {
        let t: Target = .ftpPct(value: nil, min: 95, max: 100)
        let out = svc.displayString(for: t, sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: nil)
        // 95-100 mid → 97.5 → RPE 8 (≥90 and <98 → 7? actually 97.5 is <98 so RPE 7? wait — let's verify)
        // rpeFallback table: <55→3, <65→4, <75→5, <82→6, <90→7, <98→8, <105→9, else 10
        // 97.5 → ..<98 → 8
        XCTAssertEqual(out, "RPE 8 — hard")
    }

    func test_displayString_vmaPct_resolvesToPace() {
        // VMA 18 km/h, vma_pct 90% → 16.2 km/h → 60/16.2 ≈ 3:42/km
        let t: Target = .vmaPct(value: 90, min: nil, max: nil)
        let out = svc.displayString(for: t, sport: "run", ftp: nil, vma: 18.0, css: nil, maxHr: nil)
        XCTAssertEqual(out, "3:42/km")
    }

    func test_displayString_vmaPct_range() {
        // VMA 18, 80–90% → speeds 14.4–16.2 km/h → paces 4:10–3:42; range printed fast→slow
        let t: Target = .vmaPct(value: nil, min: 80, max: 90)
        let out = svc.displayString(for: t, sport: "run", ftp: nil, vma: 18.0, css: nil, maxHr: nil)
        XCTAssertEqual(out, "3:42–4:10/km")
    }

    func test_displayString_rpe_includesDescriptor() {
        XCTAssertEqual(svc.displayString(for: .rpe(value: 6), sport: "swim", ftp: nil, vma: nil, css: nil, maxHr: nil),
                       "RPE 6 — moderate")
        XCTAssertEqual(svc.displayString(for: .rpe(value: 9), sport: "swim", ftp: nil, vma: nil, css: nil, maxHr: nil),
                       "RPE 9 — very hard")
        XCTAssertEqual(svc.displayString(for: .rpe(value: 10), sport: "swim", ftp: nil, vma: nil, css: nil, maxHr: nil),
                       "RPE 10 — max")
    }

    func test_displayString_hrZone_resolvesToBpmRange() {
        // maxHr 200, Z3 (78–85%) → lo=Int(200*0.78)=156, hi=Int(200*0.85)=170
        let out = svc.displayString(for: .hrZone(value: 3), sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: 200)
        XCTAssertEqual(out, "Z3 HR (156–170 bpm)")
    }

    func test_displayString_hrZone_noMaxHrShowsZoneLabel() {
        let out = svc.displayString(for: .hrZone(value: 3), sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "Z3 HR (set max HR in profile)")
    }

    func test_displayString_powerWatts_passesThroughRange() {
        let t: Target = .powerWatts(value: nil, min: 175, max: 190)
        let out = svc.displayString(for: t, sport: "bike", ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "175–190 W")
    }

    func test_displayString_pacePerKm_appendsUnit() {
        let out = svc.displayString(for: .pacePerKm(value: "5:30"), sport: "run",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "5:30/km")
    }

    func test_displayString_pacePer100m_appendsUnit() {
        let out = svc.displayString(for: .pacePerHundredM(value: "1:50"), sport: "swim",
                                    ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(out, "1:50/100m")
    }

    func test_displayString_cssPct_resolvesWithCss() {
        // CSS 100s/100m, css_pct 100% → 100s = 1:40/100m
        let t: Target = .cssPct(value: 100, min: nil, max: nil)
        let out = svc.displayString(for: t, sport: "swim", ftp: nil, vma: nil, css: 100, maxHr: nil)
        XCTAssertEqual(out, "1:40/100m")
    }

    func test_displayString_nilTarget_returnsNil() {
        XCTAssertNil(svc.displayString(for: nil, sport: "bike", ftp: 250, vma: nil, css: nil, maxHr: nil))
    }

    // MARK: - intensityPct — graph normalization

    func test_intensityPct_ftpPct() {
        let t: Target = .ftpPct(value: 95, min: nil, max: nil)
        let pct = svc.intensityPct(for: t, sport: "bike", ftp: 250, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(pct, 95)
    }

    func test_intensityPct_rpeMapsToTimes10() {
        let pct = svc.intensityPct(for: .rpe(value: 7), sport: "run", ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(pct, 70)
    }

    func test_intensityPct_hrZoneFollowsTable() {
        // Midpoints from hrZoneBounds: Z1=(0.50,0.65)→57.5→58, Z5=(0.92,1.00)→96.0→96
        XCTAssertEqual(svc.intensityPct(for: .hrZone(value: 1), sport: "run", ftp: nil, vma: nil, css: nil, maxHr: nil), 58)
        XCTAssertEqual(svc.intensityPct(for: .hrZone(value: 5), sport: "run", ftp: nil, vma: nil, css: nil, maxHr: nil), 96)
    }

    func test_intensityPct_pacePerKmInverts() {
        // VMA 18 km/h, pace 4:00/km → 15 km/h → 15/18 = 83%
        let t: Target = .pacePerKm(value: "4:00")
        let pct = svc.intensityPct(for: t, sport: "run", ftp: nil, vma: 18.0, css: nil, maxHr: nil)
        XCTAssertEqual(pct, 83)
    }

    func test_intensityPct_nilTarget_returnsNil() {
        XCTAssertNil(svc.intensityPct(for: nil, sport: "bike", ftp: 250, vma: nil, css: nil, maxHr: nil))
    }

    // MARK: - Swift materialize port

    func test_materialize_bikeFtpPct() {
        let tpl = WorkoutTemplate(
            templateId: "BIKE_Test",
            segments: [
                WorkoutSegment(label: "work", durationMinutes: 60, ftpPct: 65)
            ]
        )
        let s = svc.materialize(template: tpl)
        XCTAssertEqual(s.segments.count, 1)
        XCTAssertEqual(s.segments[0].label, "work")
        XCTAssertEqual(s.segments[0].durationMinutes, 60)
        XCTAssertEqual(s.segments[0].target, .ftpPct(value: 65, min: nil, max: nil))
    }

    func test_materialize_runMasPctRenamesToVmaPct() {
        let tpl = WorkoutTemplate(
            templateId: "RUN_Test",
            segments: [WorkoutSegment(label: "work", durationMinutes: 30, masPct: 75)]
        )
        let s = svc.materialize(template: tpl)
        XCTAssertEqual(s.segments[0].target, .vmaPct(value: 75, min: nil, max: nil))
    }

    func test_materialize_swimPaceMapsToRpe() {
        let cases: [(String, Double)] = [
            ("slow", 3), ("easy", 3),
            ("medium", 6),
            ("quick", 7), ("threshold", 7),
            ("fast", 8),
            ("very_quick", 9)
        ]
        for (pace, expectedRpe) in cases {
            let tpl = WorkoutTemplate(
                templateId: "SWIM_Test",
                segments: [WorkoutSegment(label: "work", distanceMeters: 100, pace: pace)]
            )
            let s = svc.materialize(template: tpl)
            XCTAssertEqual(s.segments[0].target, .rpe(value: expectedRpe), "pace=\(pace)")
        }
    }

    func test_materialize_repeatContainerHasNoTarget() {
        let tpl = WorkoutTemplate(
            templateId: "BIKE_Repeat",
            segments: [
                WorkoutSegment(
                    label: "repeat",
                    ftpPct: 80,
                    repeats: 3,
                    segments: [
                        WorkoutSegment(label: "work", durationMinutes: 5, ftpPct: 95),
                        WorkoutSegment(label: "recovery", durationMinutes: 2, ftpPct: 55)
                    ]
                )
            ]
        )
        let s = svc.materialize(template: tpl)
        let container = s.segments[0]
        XCTAssertEqual(container.repeats, 3)
        XCTAssertNil(container.target, "repeat container must not carry target")
        XCTAssertEqual(container.segments?[0].target, .ftpPct(value: 95, min: nil, max: nil))
        XCTAssertEqual(container.segments?[1].target, .ftpPct(value: 55, min: nil, max: nil))
    }

    // MARK: - flattenedSegments(structure:) — repeat expansion

    func test_flattenedSegments_expandsRepeats() {
        let structure = SessionStructure(segments: [
            StructureSegment(
                label: "repeat", repeats: 3,
                segments: [
                    StructureSegment(label: "work", durationMinutes: 5,
                                     target: .ftpPct(value: 95, min: nil, max: nil)),
                    StructureSegment(label: "recovery", durationMinutes: 2,
                                     target: .ftpPct(value: 55, min: nil, max: nil))
                ]
            )
        ])
        let flat = svc.flattenedSegments(structure: structure, sport: "bike",
                                         ftp: 250, vma: nil, css: nil, maxHr: nil)
        // 3 iterations × 2 children = 6 segments (no inter-iteration recovery since recovery is part of nested segments)
        XCTAssertEqual(flat.count, 6)
        XCTAssertEqual(flat.filter { $0.label == "work" }.count, 3)
        XCTAssertEqual(flat.filter { $0.label == "recovery" }.count, 3)
    }

    func test_flattenedSegments_addsRestBetweenRepeats() {
        let structure = SessionStructure(segments: [
            StructureSegment(
                label: "repeat", repeats: 3,
                restSeconds: 30,
                segments: [
                    StructureSegment(label: "work", distanceMeters: 100,
                                     target: .rpe(value: 7))
                ]
            )
        ])
        let flat = svc.flattenedSegments(structure: structure, sport: "swim",
                                         ftp: nil, vma: nil, css: nil, maxHr: nil)
        // 3 work + 2 inter-rep rest segments
        XCTAssertEqual(flat.count, 5)
        XCTAssertEqual(flat.filter { $0.label == "work" }.count, 3)
        XCTAssertEqual(flat.filter { $0.label == "rest" }.count, 2)
        XCTAssertTrue(flat.filter { $0.label == "rest" }.allSatisfy { $0.isRecovery })
    }

    // MARK: - StepSummary text

    func test_stepSummaries_simpleSegment_includesMetric() {
        let structure = SessionStructure(segments: [
            StructureSegment(label: "work", durationMinutes: 60,
                             target: .ftpPct(value: 65, min: nil, max: nil))
        ])
        let steps = svc.stepSummaries(structure: structure, sport: "bike",
                                      ftp: 250, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(steps.count, 1)
        // 65% of 250 = 162.5 → 163 W
        XCTAssertTrue(steps[0].text.contains("163 W"), "got: \(steps[0].text)")
    }

    func test_stepSummaries_repeatBlock_collapsesIntoOneLine() {
        let structure = SessionStructure(segments: [
            StructureSegment(
                label: "repeat", repeats: 4, restSeconds: 15,
                segments: [
                    StructureSegment(label: "work", distanceMeters: 100,
                                     target: .rpe(value: 7))
                ]
            )
        ])
        let steps = svc.stepSummaries(structure: structure, sport: "swim",
                                      ftp: nil, vma: nil, css: nil, maxHr: nil)
        XCTAssertEqual(steps.count, 1)
        XCTAssertTrue(steps[0].isRepeatBlock)
        XCTAssertTrue(steps[0].text.hasPrefix("4× "), "got: \(steps[0].text)")
        XCTAssertTrue(steps[0].text.contains("15\" rest"), "got: \(steps[0].text)")
    }

    func test_stepSummaries_includesCueWhenPresent() {
        let structure = SessionStructure(segments: [
            StructureSegment(label: "work", durationMinutes: 90,
                             target: .ftpPct(value: 62, min: nil, max: nil),
                             cue: "rolling OK")
        ])
        let steps = svc.stepSummaries(structure: structure, sport: "bike",
                                      ftp: 250, vma: nil, css: nil, maxHr: nil)
        XCTAssertTrue(steps[0].text.contains("(rolling OK)"), "got: \(steps[0].text)")
    }

    // MARK: - Distance walking

    func test_swimDistance_walksStructure() {
        let structure = SessionStructure(segments: [
            StructureSegment(label: "warmup", distanceMeters: 400, target: .rpe(value: 3)),
            StructureSegment(
                label: "repeat", repeats: 10, restSeconds: 15,
                segments: [
                    StructureSegment(label: "work", distanceMeters: 100, target: .rpe(value: 7))
                ]
            ),
            StructureSegment(label: "cooldown", distanceMeters: 200, target: .rpe(value: 3))
        ])
        let session = PlanSession(
            id: UUID(), weekId: UUID(), day: "Monday", sport: "swim",
            type: "Intervals", templateId: "SWIM_X", durationMinutes: 55,
            isBrick: false, notes: nil, orderInDay: 0, feedback: nil,
            matchedActivityId: nil, structure: structure
        )
        // 400 + (100 × 10) + 200 = 1600
        XCTAssertEqual(svc.swimDistance(for: session), 1600)
    }

    // MARK: - DRO-304: swim repeat block step text includes total block distance

    /// SWIM_Easy_03 structure: 300m warmup + 8×50m drill + 5×200m work + 300m cooldown = 2000m.
    /// The step text for each repeat block must include the total block distance so it agrees
    /// with the subtitle ("2000m"), not just the per-rep distance that naively sums to 850m.
    func test_swimRepeatBlock_stepText_appendsBlockTotal() {
        let structure = SessionStructure(segments: [
            StructureSegment(label: "warmup", distanceMeters: 300, target: .rpe(value: 3)),
            StructureSegment(
                label: "repeat", repeats: 8, restSeconds: 15,
                segments: [
                    StructureSegment(label: "drill", distanceMeters: 50, target: .rpe(value: 3))
                ]
            ),
            StructureSegment(
                label: "repeat", repeats: 5, restSeconds: 20,
                segments: [
                    StructureSegment(label: "work", distanceMeters: 200, target: .rpe(value: 3))
                ]
            ),
            StructureSegment(label: "cooldown", distanceMeters: 300, target: .rpe(value: 3))
        ])

        let steps = svc.stepSummaries(
            structure: structure, sport: "swim",
            ftp: nil, vma: nil, css: nil, maxHr: nil
        )

        // 4 step rows: warmup, 8×drill block, 5×work block, cooldown
        XCTAssertEqual(steps.count, 4)

        // Drill block: 8 × 50m = 400m total — must appear in the text
        let drillBlock = steps[1].text
        XCTAssertTrue(drillBlock.contains("8×"), "expected repeat prefix, got: \(drillBlock)")
        XCTAssertTrue(drillBlock.contains("50m"), "expected per-rep distance, got: \(drillBlock)")
        XCTAssertTrue(drillBlock.contains("400m"), "expected total block distance, got: \(drillBlock)")

        // Work block: 5 × 200m = 1000m total — must appear in the text
        let workBlock = steps[2].text
        XCTAssertTrue(workBlock.contains("5×"), "expected repeat prefix, got: \(workBlock)")
        XCTAssertTrue(workBlock.contains("200m"), "expected per-rep distance, got: \(workBlock)")
        XCTAssertTrue(workBlock.contains("1000m"), "expected total block distance, got: \(workBlock)")
    }

    /// Swim repeat block with a recovery segment that has distanceMeters:
    /// 4 × (100m work + 50m recovery) — work total = 4×100 = 400, recovery = 3×50 = 150, block = 550m.
    func test_swimRepeatBlock_stepText_includesRecoveryInTotal() {
        let structure = SessionStructure(segments: [
            StructureSegment(
                label: "repeat", repeats: 4,
                recovery: StructureSegment(label: "recovery", distanceMeters: 50, target: .rpe(value: 3)),
                segments: [
                    StructureSegment(label: "work", distanceMeters: 100, target: .rpe(value: 7))
                ]
            )
        ])

        let steps = svc.stepSummaries(
            structure: structure, sport: "swim",
            ftp: nil, vma: nil, css: nil, maxHr: nil
        )

        XCTAssertEqual(steps.count, 1)
        let text = steps[0].text
        // Block total: 4×100 + 3×50 = 400 + 150 = 550m
        XCTAssertTrue(text.contains("550m"), "expected 550m total, got: \(text)")
    }

    /// Bike repeat block must NOT get a distance suffix (bike uses duration, not meters).
    func test_bikeRepeatBlock_stepText_noDistanceSuffix() {
        let structure = SessionStructure(segments: [
            StructureSegment(
                label: "repeat", repeats: 3,
                segments: [
                    StructureSegment(label: "work", durationMinutes: 6.0,
                                     target: .ftpPct(value: nil, min: 95, max: 100))
                ]
            )
        ])

        let steps = svc.stepSummaries(
            structure: structure, sport: "bike",
            ftp: 250, vma: nil, css: nil, maxHr: nil
        )

        XCTAssertEqual(steps.count, 1)
        let text = steps[0].text
        // Should NOT contain a "· Xm" suffix
        XCTAssertFalse(text.contains("· "), "bike repeat should not have distance suffix, got: \(text)")
    }

    /// Subtitle distance must equal the sum of all fully-expanded step distances.
    /// SWIM_Easy_03: 300 + 8×50 + 5×200 + 300 = 2000m.
    func test_swimDistance_matchesExpandedStepSum_SWIM_Easy_03() {
        let structure = SessionStructure(segments: [
            StructureSegment(label: "warmup", distanceMeters: 300, target: .rpe(value: 3)),
            StructureSegment(
                label: "repeat", repeats: 8, restSeconds: 15,
                segments: [StructureSegment(label: "drill", distanceMeters: 50, target: .rpe(value: 3))]
            ),
            StructureSegment(
                label: "repeat", repeats: 5, restSeconds: 20,
                segments: [StructureSegment(label: "work", distanceMeters: 200, target: .rpe(value: 3))]
            ),
            StructureSegment(label: "cooldown", distanceMeters: 300, target: .rpe(value: 3))
        ])
        let session = PlanSession(
            id: UUID(), weekId: UUID(), day: "Wednesday", sport: "swim",
            type: "Easy", templateId: "SWIM_Easy_03", durationMinutes: 43,
            isBrick: false, notes: nil, orderInDay: 0, feedback: nil,
            matchedActivityId: nil, structure: structure
        )
        XCTAssertEqual(svc.swimDistance(for: session), 2000)
    }
}
