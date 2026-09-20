/// Every SF Symbol name the app can ask for.
///
/// A name that does not exist compiles, raises nothing at run time, and yields a
/// nil image — the menu bar item silently degrades. Names that look regular are
/// not: a variant that exists for one symbol may not exist for its sibling. So
/// the names live here, in one list, and a test asserts that each one resolves.
/// Views take their names from this type and never spell one as a literal; a
/// second test scans the app's sources to keep it that way.
public enum SymbolName {
    /// The scaffold's placeholder status item.
    public static let statusPlaceholder = "arrow.up.arrow.down"

    public static let all: [String] = [
        statusPlaceholder,
    ]
}
