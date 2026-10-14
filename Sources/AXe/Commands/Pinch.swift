import ArgumentParser
import Foundation
import FBSimulatorControl

struct Pinch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Perform a two-finger pinch gesture around a point on the screen.",
        discussion: """
        Two fingers touch down on a horizontal line through the center point, each --radius
        points away from it, then move until each is --radius * --scale points away.
        A scale greater than 1 spreads the fingers apart (zoom in); less than 1 brings them
        together (zoom out).

        Examples:
          axe pinch -x 200 -y 400 --scale 2.0 --udid SIMULATOR_UDID
          axe pinch -x 200 -y 400 --scale 0.5 --radius 100 --duration 0.8 --udid SIMULATOR_UDID
        """
    )

    static let defaultRadius: Double = 50
    static let defaultDuration: TimeInterval = 0.5
    static let defaultSteps = 20
    private static let maxSteps = 1_000
    private static let initialHold: TimeInterval = 0.05
    private static let finalHold: TimeInterval = 0.05

    @Option(name: .customShort("x"), help: "The X coordinate of the pinch center.")
    var centerX: Double

    @Option(name: .customShort("y"), help: "The Y coordinate of the pinch center.")
    var centerY: Double

    @Option(name: .customLong("scale"), help: "Ratio of the final to the initial finger distance. Greater than 1 zooms in, less than 1 zooms out.")
    var scale: Double

    @Option(name: .customLong("radius"), help: "Initial distance in points from the center to each finger.")
    var radius: Double = Self.defaultRadius

    @Option(name: .customLong("duration"), help: "Duration of the finger movement in seconds.")
    var duration: Double = Self.defaultDuration

    @Option(name: .customLong("steps"), help: "Number of touch move events to emit during the pinch.")
    var steps: Int = Self.defaultSteps

    @Option(name: .customLong("pre-delay"), help: "Delay before starting the pinch in seconds.")
    var preDelay: Double?

    @Option(name: .customLong("post-delay"), help: "Delay after completing the pinch in seconds.")
    var postDelay: Double?

    @Option(name: .customLong("udid"), help: "The UDID of the simulator.")
    var simulatorUDID: String

    func validate() throws {
        guard centerX.isFinite, centerY.isFinite, centerX >= 0, centerY >= 0 else {
            throw ValidationError("Coordinates must be non-negative values.")
        }
        guard scale.isFinite, scale > 0, scale != 1 else {
            throw ValidationError("Scale must be greater than 0 and not equal to 1.")
        }
        guard radius.isFinite, radius > 0 else {
            throw ValidationError("Radius must be greater than 0.")
        }
        guard centerX - max(radius, radius * scale) >= 0 else {
            throw ValidationError("Pinch fingers would move to negative X coordinates. Reduce --radius or --scale, or move the center right.")
        }
        guard duration.isFinite, duration > 0 else {
            throw ValidationError("Duration must be greater than 0.")
        }
        guard (1...Self.maxSteps).contains(steps) else {
            throw ValidationError("Steps must be between 1 and \(Self.maxSteps).")
        }
        if let preDelay {
            guard preDelay >= 0 && preDelay <= 10.0 else {
                throw ValidationError("Pre-delay must be between 0 and 10 seconds.")
            }
        }
        if let postDelay {
            guard postDelay >= 0 && postDelay <= 10.0 else {
                throw ValidationError("Post-delay must be between 0 and 10 seconds.")
            }
        }
    }

    func run() async throws {
        let logger = AxeLogger()
        try await setup(logger: logger)
        try await performGlobalSetup(logger: logger)

        logger.info().log("Performing pinch at (\(centerX), \(centerY)) with scale \(scale)")
        logger.info().log("Radius: \(radius), duration: \(duration)s, steps: \(steps)")

        let pinchEvent = try await makePinchEvent(for: simulatorUDID, logger: logger)

        var events: [FBSimulatorHIDEvent] = []
        if let preDelay, preDelay > 0 {
            logger.info().log("Pre-delay: \(preDelay)s")
            events.append(.delay(preDelay))
        }
        events.append(pinchEvent)
        if let postDelay, postDelay > 0 {
            logger.info().log("Post-delay: \(postDelay)s")
            events.append(.delay(postDelay))
        }

        try await HIDInteractor.performHIDEvent(
            events.count == 1 ? events[0] : .composite(events),
            for: simulatorUDID,
            logger: logger
        )

        logger.info().log("Pinch gesture completed successfully")
    }

    /// Builds the pinch as one composite HID event, translating every finger position to physical coordinates.
    @MainActor
    func makePinchEvent(for simulatorUDID: String, logger: AxeLogger) async throws -> FBSimulatorHIDEvent {
        let logicalPositions = try HIDInteractor.pinchFingerPositions(
            center: (x: centerX, y: centerY),
            startRadius: radius,
            endRadius: radius * scale,
            steps: steps
        )

        let physicalPoints = try await OrientationAwareCoordinates.translateBatch(
            points: logicalPositions.flatMap { [$0.finger1, $0.finger2] },
            for: simulatorUDID,
            logger: logger
        )
        let physicalPositions = stride(from: 0, to: physicalPoints.count, by: 2).map { index in
            HIDInteractor.PinchFingerPositions(finger1: physicalPoints[index], finger2: physicalPoints[index + 1])
        }

        return try HIDInteractor.makeCompositePinchEvent(
            positions: physicalPositions,
            duration: duration,
            initialHold: Self.initialHold,
            finalHold: Self.finalHold
        )
    }
}
