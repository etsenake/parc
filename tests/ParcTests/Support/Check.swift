import Testing

func check(_ condition: Bool, _ message: @autoclosure () -> String, sourceLocation: SourceLocation = #_sourceLocation) {
    if !condition { Issue.record(Comment(rawValue: message()), sourceLocation: sourceLocation) }
}
