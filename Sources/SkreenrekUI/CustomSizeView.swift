import SkreenrekCore
import SwiftUI

/// Width and height in px, with the points equivalent below in 12 pt secondary text.
struct CustomSizeView: View {
    @State var model: CustomSizeModel
    let finish: (PixelSize?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIStrings.CustomSize.title).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 12) {
                field(UIStrings.CustomSize.width, text: $model.widthText)
                Text(UIStrings.CustomSize.times).foregroundStyle(.secondary)
                field(UIStrings.CustomSize.height, text: $model.heightText)
            }
            Text(model.caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(UIStrings.CustomSize.cancel) { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(UIStrings.CustomSize.setSize) { finish(model.size) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isValid)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(label), \(UIStrings.CustomSize.px)")
            Text(UIStrings.CustomSize.px).foregroundStyle(.secondary)
        }
    }
}
