import GranularCore
import SwiftUI

/// Names the look in the camera and packages it in a canister, then saves it
/// as a recipe of its own.
struct SaveRecipeSheet: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var canister = ""
    @State private var didSave = false
    @FocusState private var isNaming: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var design: CanisterDesign {
        CanisterDesign.named(canister) ?? CanisterDesign.automatic[0]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                FilmCanisterView(
                    style: CanisterStyle(design: design, recipe: darkroom.recipe),
                    recipeName: trimmedName.isEmpty ? "Recipe" : trimmedName,
                    height: 150
                )
                .frame(width: CanisterGeometry.width * 150 / CanisterGeometry.height, height: 150)

                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .focused($isNaming)
                    .onSubmit(save)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 24)

                canisters
            }
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Save Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .sensoryFeedback(.success, trigger: didSave)
        .sensoryFeedback(.selection, trigger: canister)
        .onAppear {
            let current = darkroom.recipe
            let isSaved = darkroom.isSavedRecipe(darkroom.selectedRecipeID)
            name = isSaved ? current.name : "My Recipe"
            canister = isSaved
                ? CanisterDesign.resolved(for: current).id
                : CanisterDesign.automatic.randomElement()?.id ?? ""
            isNaming = true
        }
    }

    /// Every design in the library, the chosen one ringed.
    private var canisters: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(CanisterDesign.library) { option in
                        Button {
                            withAnimation(.smooth) { canister = option.id }
                        } label: {
                            FilmCanisterView(
                                style: CanisterStyle(design: option, recipe: darkroom.recipe),
                                recipeName: trimmedName.isEmpty ? "Recipe" : trimmedName,
                                height: 64,
                                castsShadow: false
                            )
                            .frame(width: CanisterGeometry.width * 64 / CanisterGeometry.height, height: 64)
                            .padding(6)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                                    .opacity(option.id == canister ? 1 : 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(option.id)
                        .accessibilityLabel(option.name)
                        .accessibilityAddTraits(option.id == canister ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: canister, initial: true) { _, id in
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func save() {
        guard !didSave, !trimmedName.isEmpty else { return }
        didSave = true
        withAnimation(.smooth) {
            _ = darkroom.saveCurrentAsRecipe(named: trimmedName, canister: canister)
        }
        dismiss()
    }
}
