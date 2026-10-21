public enum DevicePolicy {
    public static func shouldPauseForLid(closed: Bool, externalDisplayActive: Bool, allowExternalWork: Bool) -> Bool {
        closed && !(externalDisplayActive && allowExternalWork)
    }
}
