import AppKit
import ApplicationServices

@MainActor
protocol ScreenshotAutoSelectionDetecting {
    func autoSelectionRect(
        at screenPoint: CGPoint,
        excludingWindowIDs: Set<CGWindowID>
    ) -> CGRect?
}

@MainActor
struct SystemScreenshotAutoSelectionDetector: ScreenshotAutoSelectionDetecting {
    func autoSelectionRect(
        at screenPoint: CGPoint,
        excludingWindowIDs: Set<CGWindowID>
    ) -> CGRect? {
        guard let window = WindowBoundsDetector.window(
            at: screenPoint,
            excludingWindowIDs: excludingWindowIDs
        ) else {
            return nil
        }

        if let accessibilityRect = AccessibilityElementBoundsDetector.rect(
            at: screenPoint,
            inApplicationWithProcessID: window.ownerPID
        ) {
            return accessibilityRect
        }

        return window.rect
    }
}

private enum AccessibilityElementBoundsDetector {
    @MainActor
    static func rect(
        at screenPoint: CGPoint,
        inApplicationWithProcessID processID: pid_t
    ) -> CGRect? {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(processID)
        var element: AXUIElement?
        let accessibilityPoint = ScreenCoordinateConverter.topLeftPoint(fromAppKitPoint: screenPoint)
        let result = AXUIElementCopyElementAtPosition(
            applicationElement,
            Float(accessibilityPoint.x),
            Float(accessibilityPoint.y),
            &element
        )
        guard result == .success,
              let element,
              let rect = rect(for: element),
              rect.contains(screenPoint),
              rect.isUsableAutoSelection else {
            return nil
        }

        return rect
    }

    private static func rect(for element: AXUIElement) -> CGRect? {
        guard let position = value(
            for: kAXPositionAttribute,
            in: element,
            as: CGPoint.self
        ),
        let size = value(
            for: kAXSizeAttribute,
            in: element,
            as: CGSize.self
        ) else {
            return nil
        }

        return ScreenCoordinateConverter.appKitRect(
            fromTopLeftRect: CGRect(origin: position, size: size)
        )?
        .standardized
    }

    private static func value<T>(
        for attribute: String,
        in element: AXUIElement,
        as type: T.Type
    ) -> T? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &rawValue
        )
        guard result == .success,
              let rawValue,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = rawValue as! AXValue
        if T.self == CGPoint.self {
            var point = CGPoint.zero
            guard AXValueGetValue(axValue, .cgPoint, &point) else {
                return nil
            }
            return point as? T
        }

        if T.self == CGSize.self {
            var size = CGSize.zero
            guard AXValueGetValue(axValue, .cgSize, &size) else {
                return nil
            }
            return size as? T
        }

        return nil
    }
}

private struct DetectedWindow {
    let rect: CGRect
    let ownerPID: pid_t
}

private enum WindowBoundsDetector {
    static func window(
        at screenPoint: CGPoint,
        excludingWindowIDs: Set<CGWindowID>
    ) -> DetectedWindow? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return windows.compactMap { info -> DetectedWindow? in
            guard let windowID = info[kCGWindowNumber as String] as? NSNumber,
                  !excludingWindowIDs.contains(windowID.uint32Value),
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let alpha = info[kCGWindowAlpha as String] as? NSNumber,
                  alpha.doubleValue > 0.05,
                  let boundsValue = info[kCGWindowBounds as String] as? [String: Any],
                  let topLeftRect = CGRect(dictionaryRepresentation: boundsValue as CFDictionary),
                  let rect = ScreenCoordinateConverter.appKitRect(fromTopLeftRect: topLeftRect),
                  rect.contains(screenPoint),
                  rect.isUsableAutoSelection else {
                return nil
            }

            return DetectedWindow(rect: rect.standardized, ownerPID: ownerPID.int32Value)
        }
        .first
    }
}

enum ScreenCoordinateConverter {
    static func topLeftPoint(fromAppKitPoint point: CGPoint) -> CGPoint {
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(point)
        } ?? NSScreen.main

        guard let screen,
              let topLeftScreenFrame = screen.topLeftCoordinateFrame else {
            return point
        }

        return CGPoint(
            x: topLeftScreenFrame.minX + (point.x - screen.frame.minX),
            y: topLeftScreenFrame.maxY - (point.y - screen.frame.minY)
        )
    }

    static func appKitRect(fromTopLeftRect rect: CGRect) -> CGRect? {
        let standardizedRect = rect.standardized
        let center = CGPoint(
            x: standardizedRect.midX,
            y: standardizedRect.midY
        )
        let screen = NSScreen.screens.first { screen in
            screen.topLeftCoordinateFrame?.contains(center) == true
        } ?? NSScreen.main

        guard let screen,
              let topLeftScreenFrame = screen.topLeftCoordinateFrame else {
            return nil
        }

        return CGRect(
            x: screen.frame.minX + (standardizedRect.minX - topLeftScreenFrame.minX),
            y: screen.frame.minY + (topLeftScreenFrame.maxY - standardizedRect.maxY),
            width: standardizedRect.width,
            height: standardizedRect.height
        )
    }
}

private extension NSScreen {
    var topLeftCoordinateFrame: CGRect? {
        guard let displayID = deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID else {
            return nil
        }

        return CGDisplayBounds(displayID)
    }
}

private extension CGRect {
    var isUsableAutoSelection: Bool {
        width >= ScreenshotSelectionGeometry.minimumSize.width
            && height >= ScreenshotSelectionGeometry.minimumSize.height
            && width.isFinite
            && height.isFinite
    }
}
