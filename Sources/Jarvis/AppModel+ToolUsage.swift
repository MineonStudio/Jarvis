extension AppModel {
    /// Count the entry action, including repeated clicks on the current tool.
    /// Programmatic navigation (for example, after a capture) is not an entry.
    func openTool(_ tool: SkillID) {
        toolUsage.recordOpen(tool)
        selectedSection = .skill(tool)
    }
}
