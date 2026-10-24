import Foundation

/// The disk image an app bundle runs from, if any.
enum DiskImage {
    /// The mounted disk image volume containing `bundleURL`, looking through App Translocation.
    static func volume(containing bundleURL: URL) -> URL? {
        let original = originalURL(of: bundleURL)
        guard original.path.hasPrefix("/Volumes/"),
              let values = try? original.resourceValues(forKeys: [.volumeURLKey, .volumeIsReadOnlyKey]),
              values.volumeIsReadOnly == true
        else { return nil }
        return values.volume
    }

    /// Where the bundle really is. An app opened from a downloaded disk image runs from a
    /// randomized read-only copy under AppTranslocation, which hides the disk image's volume.
    /// The Security functions that undo this are exported but missing from the Swift headers,
    /// so they are looked up at runtime, as LetsMove and Sparkle do.
    static func originalURL(of bundleURL: URL) -> URL {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let isTranslocatedSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL"),
              let originalPathSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return bundleURL }
        let isTranslocatedURL = unsafeBitCast(isTranslocatedSymbol, to: IsTranslocated.self)
        let originalPath = unsafeBitCast(originalPathSymbol, to: OriginalPath.self)

        var isTranslocated = false
        guard isTranslocatedURL(bundleURL as CFURL, &isTranslocated, nil).boolValue, isTranslocated,
              let original = originalPath(bundleURL as CFURL, nil)?.takeRetainedValue()
        else { return bundleURL }
        return original as URL
    }
}
