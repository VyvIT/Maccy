import Foundation
import Defaults

// How the preview of the selected history item is opened.
enum PreviewOpening: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  // After the preview delay
  case delay
  // With → and closed with ←
  case arrowKeys

  var id: Self { self }

  var description: String {
    switch self {
    case .delay:
      return NSLocalizedString("OpenPreviewDelay", tableName: "AppearanceSettings", comment: "")
    case .arrowKeys:
      return NSLocalizedString("OpenPreviewArrowKeys", tableName: "AppearanceSettings", comment: "")
    }
  }
}
