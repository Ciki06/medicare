import SwiftUI
import WidgetKit

extension View {
  @ViewBuilder
  func medicareWidgetBackground<Background: View>(
    @ViewBuilder _ background: () -> Background
  ) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) {
        background()
      }
    } else {
      self.background(background())
    }
  }
}
