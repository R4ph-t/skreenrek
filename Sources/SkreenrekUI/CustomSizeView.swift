import SkreenrekCore
import SwiftUI

/// Spec 13's Custom Size panel: 320 pt, radius 10, W × H in clip px, a quiet live line (or the reason in 12 pt red),
/// Cancel and Set Size (the default button).
struct CustomSizeView: View {
    @State var model: CustomSizeModel
    let finish: (PixelSize?) -> Void
    /// Renders draw the panel as the key window (an offscreen window never is).
    var drawsAsKey = false

    static let width: CGFloat = 320
    static let cornerRadius: CGFloat = 10

    var body: some View {
        let panel = VStack(alignment: .leading, spacing: 12) {
            Text(UIStrings.CustomSize.title).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                field(UIStrings.CustomSize.width, text: $model.widthText)
                Text(UIStrings.CustomSize.times).foregroundStyle(.secondary)
                field(UIStrings.CustomSize.height, text: $model.heightText)
                Text(UIStrings.CustomSize.px).foregroundStyle(.secondary)
            }
            line
            HStack(spacing: 8) {
                Spacer()
                Button(UIStrings.CustomSize.cancel) { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(UIStrings.CustomSize.setSize) {
                    model.snap()
                    finish(model.size)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isValid)
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color(nsColor: SkreenrekSurface.baseColor)))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor)))
        if drawsAsKey {
            panel.environment(\.controlActiveState, .key)
        } else {
            panel
        }
    }

    @ViewBuilder private var line: some View {
        switch model.line {
        case .quiet(let text):
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        case .problem(let text):
            Text(text).font(.system(size: 12)).foregroundStyle(Color(nsColor: .systemRed))
        case .none:
            EmptyView()
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 96)
            .multilineTextAlignment(.trailing)
            .onSubmit { model.snap() }
            .accessibilityLabel("\(label), \(UIStrings.CustomSize.px)")
    }
}
