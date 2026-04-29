import SwiftUI
import CoreLocation

// MARK: - Reusable place autocomplete field.
//
// Same UX as the Search screen's "From / To" fields: type → debounced query
// against VoygoLocationService (MapKit) with a Nominatim/Voygo backend
// fallback → tap a suggestion to autofill. Used by Create Route's Start /
// Destination and by the pickup/drop stop entry rows.
//
// Exposes both the typed text *and* the lat/lng of the picked suggestion so
// callers can store coordinates when one was selected (start/end), or just
// the label string when only the name matters (free-form pickup stops).

struct PlaceLookupField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    /// Optional coordinate setter — set when the user picks a suggestion,
    /// cleared when they edit the text again. Pass nil if you only need the
    /// display name (e.g. pickup-stop entry).
    var onSelect: ((PlaceSuggestion) -> Void)? = nil
    /// Called every time the user types — useful when the parent wants to
    /// invalidate cached coordinates as soon as the field is edited.
    var onTextChange: ((String) -> Void)? = nil

    @State private var suggestions: [PlaceSuggestion] = []
    @State private var isLoading = false
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var lastAcceptedQuery: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VoygoTextField(label: label, text: $text, placeholder: placeholder)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    onTextChange?(newValue)
                    // If the user just accepted a suggestion, ignore the
                    // synthetic change that follows from setting the binding.
                    if newValue == lastAcceptedQuery { return }
                    suggest(query: newValue)
                }

            if isFocused, !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            accept(suggestion)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(VoygoTheme.primary)
                                    .font(.subheadline)
                                Text(suggestion.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(VoygoTheme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if suggestion.id != suggestions.last?.id {
                            Divider().background(VoygoTheme.cardBorder)
                        }
                    }
                }
                .background(VoygoTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(VoygoTheme.cardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            } else if isFocused, isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching places…")
                        .font(.caption)
                        .foregroundColor(VoygoTheme.textHint)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: suggestions)
        .animation(.easeInOut(duration: 0.18), value: isLoading)
    }

    private func suggest(query: String) {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            isLoading = false
            return
        }
        isLoading = true
        debounceTask = Task {
            // Debounce 400ms — same window the Search screen uses, so we
            // don't have two screens with conflicting "feels".
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }

            let bias = await VoygoLocationService.shared.lastKnownCoordinate()
            if Task.isCancelled || trimmed != currentTrimmedQuery() { return }

            // Try MapKit first (richer for MY-specific places). Backend
            // (Nominatim) is the fallback when offline or empty.
            var results: [PlaceSuggestion] = []
            if let mk = try? await VoygoLocationService.shared.searchPlaces(query: trimmed, near: bias),
               !mk.isEmpty {
                results = mk
            } else if let api = try? await VoygoAPIClient.autocompletePlaces(
                query: trimmed, lat: bias?.latitude, lon: bias?.longitude
            ) {
                results = api
            }

            if Task.isCancelled || trimmed != currentTrimmedQuery() { return }
            await MainActor.run {
                self.suggestions = Array(results.prefix(6))
                self.isLoading = false
            }
        }
    }

    private func accept(_ suggestion: PlaceSuggestion) {
        lastAcceptedQuery = suggestion.displayName
        text = suggestion.displayName
        suggestions = []
        isLoading = false
        isFocused = false
        onSelect?(suggestion)
    }

    private func currentTrimmedQuery() -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
