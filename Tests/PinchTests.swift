import Testing
import Foundation
import FBSimulatorControl
@testable import AXe

@Suite("Pinch Command Surface Tests")
struct PinchCommandSurfaceTests {
    @Test("Pinch help includes center, scale, and timing options")
    func pinchHelpIncludesCenterScaleAndTimingOptions() async throws {
        let result = try await TestHelpers.runAxeCommand("pinch --help")

        #expect(result.output.contains("-x <x>"))
        #expect(result.output.contains("-y <y>"))
        #expect(result.output.contains("--scale"))
        #expect(result.output.contains("--radius"))
        #expect(result.output.contains("--duration"))
        #expect(result.output.contains("--steps"))
    }

    @Test("Scale of 1 fails validation")
    func scaleOfOneFailsValidation() async throws {
        let result = try await TestHelpers.runAxeCommandAllowFailure(
            "pinch -x 200 -y 400 --scale 1 --udid invalid"
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("Scale must be greater than 0 and not equal to 1."))
    }

    @Test("Non-finite center or duration fails validation", arguments: [
        "-x inf -y 400 --scale 2",
        "-x 200 -y inf --scale 2",
        "-x 200 -y 400 --scale 2 --duration inf"
    ])
    func nonFiniteValuesFailValidation(arguments: String) async throws {
        let result = try await TestHelpers.runAxeCommandAllowFailure(
            "pinch \(arguments) --udid invalid"
        )

        #expect(result.exitCode != 0)
        #expect(
            result.output.contains("Coordinates must be non-negative values.")
                || result.output.contains("Duration must be greater than 0.")
        )
    }

    @Test("Fingers moving to negative X fail validation")
    func fingersMovingToNegativeXFailValidation() async throws {
        let result = try await TestHelpers.runAxeCommandAllowFailure(
            "pinch -x 100 -y 400 --scale 3 --radius 50 --udid invalid"
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("Pinch fingers would move to negative X coordinates."))
    }

    @Test("Too many pinch steps fails validation")
    func tooManyPinchStepsFailsValidation() async throws {
        let result = try await TestHelpers.runAxeCommandAllowFailure(
            "pinch -x 200 -y 400 --scale 2 --steps 1001 --udid invalid"
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("Steps must be between 1 and 1000."))
    }

    @Test("Pinch finger positions spread symmetrically from the start to the end radius")
    @MainActor
    func pinchFingerPositionsSpreadSymmetrically() throws {
        let positions = try HIDInteractor.pinchFingerPositions(
            center: (x: 200, y: 400),
            startRadius: 50,
            endRadius: 100,
            steps: 5
        )

        #expect(positions.count == 6)
        #expect(positions.first?.finger1.x == 150)
        #expect(positions.first?.finger2.x == 250)
        #expect(positions.last?.finger1.x == 100)
        #expect(positions.last?.finger2.x == 300)
        #expect(positions.allSatisfy { $0.finger1.y == 400 && $0.finger2.y == 400 })
        #expect(positions.allSatisfy { $0.finger1.x + $0.finger2.x == 400 })
    }

    @Test("Composite pinch event touches down, moves both fingers, then lifts at the end positions")
    @MainActor
    func compositePinchEventSequence() throws {
        let positions = try HIDInteractor.pinchFingerPositions(
            center: (x: 200, y: 400),
            startRadius: 100,
            endRadius: 50,
            steps: 2
        )
        let event = try HIDInteractor.makeCompositePinchEvent(
            positions: positions,
            duration: 0.2,
            initialHold: 0.05,
            finalHold: 0.05
        )

        let expected: [FBSimulatorHIDEvent] = [
            .twoFingerTouch(direction: .down, finger1: CGPoint(x: 100, y: 400), finger2: CGPoint(x: 300, y: 400)),
            .delay(0.05),
            .delay(0.1),
            .twoFingerTouch(direction: .down, finger1: CGPoint(x: 125, y: 400), finger2: CGPoint(x: 275, y: 400)),
            .delay(0.1),
            .twoFingerTouch(direction: .down, finger1: CGPoint(x: 150, y: 400), finger2: CGPoint(x: 250, y: 400)),
            .delay(0.05),
            .twoFingerTouch(direction: .up, finger1: CGPoint(x: 150, y: 400), finger2: CGPoint(x: 250, y: 400))
        ]
        #expect(event == .composite(expected))
    }

    @Test("Composite pinch event requires at least one move position")
    @MainActor
    func compositePinchEventRequiresMovePosition() throws {
        let start = HIDInteractor.PinchFingerPositions(finger1: (x: 100, y: 400), finger2: (x: 300, y: 400))

        #expect(throws: CLIError.self) {
            try HIDInteractor.makeCompositePinchEvent(
                positions: [start],
                duration: 0.2,
                initialHold: 0.05,
                finalHold: 0.05
            )
        }
    }
}
