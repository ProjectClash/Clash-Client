enum ClashHubNavigationPolicy {
    static func usesSelection(
        presentationClass: ClashPresentationClass,
        supportsNavigationStack: Bool
    ) -> Bool {
        // The iOS 15 split view does not consume the shell's navigation path.
        supportsNavigationStack
            && (presentationClass == .regularTouch || presentationClass == .desktop)
    }

    static func usesSelection(for presentationClass: ClashPresentationClass) -> Bool {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            return usesSelection(
                presentationClass: presentationClass,
                supportsNavigationStack: true
            )
        }
        return false
    }
}
