import AppKit

enum WindowSelection {
    // Read once before presenting overlays; WindowServer returns front-to-back order.
    @MainActor static func current() -> [CGRect] {
        guard let screen = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return [] }
        return frames(from: windows, primaryScreenTop: screen.frame.maxY,
                      ownPID: ProcessInfo.processInfo.processIdentifier,
                      pinnedIDs: ScreenSnapshotSource.pinnedWindowIDs())
    }
    static func frames(from windows: [[String: Any]], primaryScreenTop: CGFloat,
                       ownPID: Int32, pinnedIDs: Set<CGWindowID>) -> [CGRect] {
        windows.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? NSNumber,
                  let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  let alpha = info[kCGWindowAlpha as String] as? NSNumber,
                  alpha.doubleValue > 0,
                  let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  !rect.isInfinite, !rect.isNull, rect.width >= 2, rect.height >= 2 else { return nil }
            let pinned = pid.int32Value == ownPID && pinnedIDs.contains(id.uint32Value)
            guard pinned || (pid.int32Value != ownPID && layer.intValue == 0) else { return nil }
            // Quartz uses a top-left origin; NSScreen uses a bottom-left origin.
            return CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
        }
    }
    static func localFrames(_ frames: [CGRect], display: CGRect) -> [CGRect] {
        frames.compactMap { frame in
            let clipped = frame.intersection(display)
            guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
            return CGRect(x: clipped.minX - display.minX, y: display.maxY - clipped.maxY,
                          width: clipped.width, height: clipped.height)
        }
    }
}
