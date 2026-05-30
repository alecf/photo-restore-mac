import SwiftUI
import RestoreEngine

/// Mac-native settings inspector — not a CLI-flag dump. Size + a single restoration-intensity
/// slider up top; everything else under Advanced. Always visible; changes apply live to whatever
/// restores next (and enable per-photo "redo" when they diverge from a photo's last result).
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Output size") {
                    Picker("Size", selection: $model.sizeChoice) {
                        ForEach(AppModel.SizeChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if model.sizeChoice == .custom {
                        HStack {
                            TextField("Width", text: $model.customWidth).frame(width: 80)
                            Text("×").foregroundStyle(.secondary)
                            TextField("Height", text: $model.customHeight).frame(width: 80)
                            Text("fit inside (aspect preserved; leave one blank)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Face restoration") {
                    Toggle("Restore faces", isOn: $model.faceEnabled)
                    if model.faceEnabled {
                        VStack(alignment: .leading) {
                            Slider(value: $model.restorationIntensity, in: 0...1) {
                                Text("Intensity")
                            } minimumValueLabel: {
                                Text("Subtle").font(.caption)
                            } maximumValueLabel: {
                                Text("Full").font(.caption)
                            }
                            Text("Lower keeps more of the real skin texture.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                DisclosureGroup("Advanced") {
                    if model.faceEnabled {
                        Toggle("Match original color (B&W / sepia safe)", isOn: $model.matchColor)
                        Toggle("Match film grain", isOn: $model.matchGrain)
                        Toggle("Skip already-sharp faces", isOn: $model.skipLargeFaces)
                    }
                    Toggle("Auto-contrast faded scans", isOn: $model.autoContrast)
                    Picker("Format", selection: $model.outputFormat) {
                        Text("Keep (PNG / JPEG)").tag(OutputFormat.keep)
                        Text("PNG").tag(OutputFormat.png)
                        Text("JPEG").tag(OutputFormat.jpeg)
                    }
                    if model.outputFormat == .jpeg {
                        Stepper("JPEG quality: \(model.jpegQuality)", value: $model.jpegQuality, in: 1...100, step: 5)
                    }
                    Toggle("Overwrite existing outputs", isOn: $model.overwrite)
                    Toggle("Include subfolders", isOn: $model.includeSubfolders)
                }
            }
            .formStyle(.grouped)
        }
    }
}
