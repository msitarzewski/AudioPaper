import AppKit
import CoreGraphics

/// Which desktop (Space) each display is showing, so a wallpaper can be put back on the Space it came from.
///
/// macOS gives every Space its own wallpaper but has no public API naming Spaces. This asks the window
/// server's private `SLSManagedDisplayGetCurrentSpace` (also exported as `CGS…`), looked up at run time, as
/// window and wallpaper utilities do. If a future macOS removes it, `currentSpace` returns nil and AudioPaper
/// falls back to one remembered wallpaper per display.
enum Spaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64

    nonisolated(unsafe) private static let anyImage = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT

    nonisolated(unsafe) private static let mainConnection: MainConnection? =
        symbol(["SLSMainConnectionID", "CGSMainConnectionID"], MainConnection.self)
    nonisolated(unsafe) private static let currentSpaceOfDisplay: CurrentSpace? =
        symbol(["SLSManagedDisplayGetCurrentSpace", "CGSManagedDisplayGetCurrentSpace"], CurrentSpace.self)

    private static func symbol<T>(_ names: [String], _ type: T.Type) -> T? {
        for name in names {
            if let pointer = dlsym(anyImage, name) { return unsafeBitCast(pointer, to: type) }
        }
        return nil
    }

    /// A display's stable identifier (it survives reconnects, unlike the display number).
    static func displayUUID(_ displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// The Space the display is showing now, or nil if the window server won't say.
    static func currentSpace(onDisplay uuid: String) -> UInt64? {
        guard let mainConnection, let currentSpaceOfDisplay else { return nil }
        let space = currentSpaceOfDisplay(mainConnection(), uuid as CFString)
        return space == 0 ? nil : space
    }
}
