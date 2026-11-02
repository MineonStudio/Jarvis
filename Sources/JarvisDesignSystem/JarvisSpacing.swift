import Foundation

/// Shared spacing for the app and the separately compiled LAN transfer module.
/// Use a role rather than a local number so equivalent surfaces stay aligned.
/// Zero spacing remains intentional for adjoining panes and divider boundaries.
public enum JarvisSpacing {
    public static let hairline: CGFloat = 2
    public static let textGap: CGFloat = 4
    public static let iconGap: CGFloat = 6
    public static let controlGap: CGFloat = 8
    public static let itemGap: CGFloat = 12
    public static let groupGap: CGFloat = 16
    public static let sectionGap: CGFloat = 20
    public static let pageInset: CGFloat = 24
    public static let spacious: CGFloat = 32
    public static let heroInset: CGFloat = 40

    public static let rowInset = itemGap
    public static let cardInset = groupGap
    public static let panelInset = groupGap
    public static let gridGap = itemGap
    public static let columnGap = itemGap
    public static let buttonHorizontalInset = groupGap
    public static let buttonVerticalInset = controlGap
}
