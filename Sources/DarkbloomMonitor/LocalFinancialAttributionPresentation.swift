/// Account-wide credits remain useful, but do not identify local serving income.
enum LocalFinancialAttributionPresentation {
    static let unavailableMessage = "Account credits aren't yet linked to this Mac. Gross account earnings remain available."
    static let powerWaitingMessage = "Local earnings aren't verified for this Mac."
    static let localHelp = "Estimated profit requires verified earnings for this Mac and matching whole-Mac power observations. Missing attribution or coverage remains unavailable."
    static let accountHelp = "Recorded account credits may include other owned machines. They do not establish what this Mac earned. Missing history is unknown, not zero."
}
