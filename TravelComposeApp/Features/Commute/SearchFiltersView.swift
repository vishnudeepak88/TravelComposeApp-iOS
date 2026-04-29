import SwiftUI

// MARK: - Search & Filters (mirrors SearchFiltersScreen.jsx)

struct SearchFiltersView: View {
    @Binding var routeQuery: String
    @Binding var earliest: String
    @Binding var latest: String
    @Binding var days: DaysOfWeekFlags
    var onApply: () -> Void
    var onBack: () -> Void

    @State private var verifiedOnly = true
    @State private var minRating = true
    @State private var sameGender = false
    @State private var malayLanguage = false
    @State private var evOnly = true
    @State private var sedan = false
    @State private var suv = true
    @State private var smallSeats = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                VPolishedNavBar(title: "Find a route", onBack: onBack) {
                    Text("Reset").font(.system(size: 12, weight: .bold)).foregroundColor(VPalette.primary)
                }

                ScrollView {
                    VStack(spacing: 18) {
                        searchPill
                        section("Departure window") { departureSection }
                        section("Days") { daysSection }
                        section("Price per ride", trailing: "RM 6 – RM 18") { priceHistogram }
                        section("Vehicle") { vehicleChips }
                        section("Driver preferences") { driverPrefs }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
            }

            VStack {
                VPrimaryButton("Show 14 routes", action: onApply)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(.ultraThinMaterial)
            .background(VPalette.bg.opacity(0.6))
            .overlay(Rectangle().fill(VPalette.border).frame(height: 1), alignment: .top)
        }
        .navigationBarHidden(true)
    }

    private var searchPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill").foregroundColor(VPalette.primary)
            Text(routeQuery.isEmpty ? "Where are you commuting?" : routeQuery)
                .font(.system(size: 14, weight: .heavy)).foregroundColor(VPalette.text)
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12)).foregroundColor(VPalette.textHint)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(VPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VKicker(text: title)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(VPalette.text)
                }
            }
            content()
        }
    }

    private var departureSection: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    VKicker(text: "Earliest", size: 9)
                    Text(earliest)
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundColor(VPalette.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    VKicker(text: "Latest", size: 9)
                    Text(latest)
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundColor(VPalette.primary)
                }
            }
            // Two real native Sliders backed by minutes-since-midnight,
            // formatted back to "HH:mm" through the bindings. The
            // previous decorative GeometryReader handles never moved
            // because there was no DragGesture.
            VStack(spacing: 8) {
                Slider(value: earliestMinutesBinding, in: 5*60...11*60, step: 15)
                    .tint(VPalette.primary)
                    .accessibilityLabel("Earliest departure time")
                Slider(value: latestMinutesBinding, in: 5*60...11*60, step: 15)
                    .tint(VPalette.primary)
                    .accessibilityLabel("Latest departure time")
            }
            HStack {
                ForEach(["5:00", "7:00", "9:00", "11:00"], id: \.self) { t in
                    Text(t)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(VPalette.textHint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(VPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Wrap the "HH:mm" string bindings as Doubles in minutes so SwiftUI
    /// `Slider` can drive them. Both setters clamp against an atomic
    /// snapshot of the *current parsed bounds* rather than re-reading the
    /// other binding mid-update — without this, dragging earliest past
    /// latest causes a jitter where SwiftUI re-renders and the next setter
    /// reads a stale upper bound.
    private var earliestMinutesBinding: Binding<Double> {
        Binding(
            get: { Double(parseMinutes(earliest) ?? (7 * 60)) },
            set: { newValue in
                let upper = parseMinutes(latest) ?? (9 * 60)
                let proposed = Int(newValue)
                let clamped = min(proposed, upper)
                let asString = formatMinutes(clamped)
                if asString != earliest { earliest = asString }
            }
        )
    }

    private var latestMinutesBinding: Binding<Double> {
        Binding(
            get: { Double(parseMinutes(latest) ?? (9 * 60)) },
            set: { newValue in
                let lower = parseMinutes(earliest) ?? (7 * 60)
                let proposed = Int(newValue)
                let clamped = max(proposed, lower)
                let asString = formatMinutes(clamped)
                if asString != latest { latest = asString }
            }
        )
    }

    private func parseMinutes(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let h = max(0, min(23, minutes / 60))
        let m = max(0, min(59, minutes % 60))
        return String(format: "%02d:%02d", h, m)
    }

    private var daysSection: some View {
        let dayPairs: [(String, KeyPath<DaysOfWeekFlags, Bool>)] = [
            ("M", \.monday), ("T", \.tuesday), ("W", \.wednesday),
            ("T", \.thursday), ("F", \.friday), ("S", \.saturday), ("S", \.sunday)
        ]
        return HStack(spacing: 6) {
            ForEach(0..<dayPairs.count, id: \.self) { i in
                let on = days[keyPath: dayPairs[i].1]
                Text(dayPairs[i].0)
                    .font(.system(size: 13, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundColor(on ? VPalette.primary : VPalette.textHint)
                    .background(on ? VPalette.primaryContainer : VPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? VPalette.primary : VPalette.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture {
                        let kp = dayPairs[i].1
                        switch kp {
                        case \DaysOfWeekFlags.monday:    days.monday.toggle()
                        case \DaysOfWeekFlags.tuesday:   days.tuesday.toggle()
                        case \DaysOfWeekFlags.wednesday: days.wednesday.toggle()
                        case \DaysOfWeekFlags.thursday:  days.thursday.toggle()
                        case \DaysOfWeekFlags.friday:    days.friday.toggle()
                        case \DaysOfWeekFlags.saturday:  days.saturday.toggle()
                        case \DaysOfWeekFlags.sunday:    days.sunday.toggle()
                        default: break
                        }
                    }
            }
        }
    }

    private var priceHistogram: some View {
        let bars: [Int] = [20, 30, 45, 70, 90, 100, 80, 65, 40, 30, 22, 18, 14, 10, 6]
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<bars.count, id: \.self) { i in
                let active = i >= 1 && i <= 12
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(active ? VPalette.primary : VPalette.border)
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(bars[i]) * 0.5)
            }
        }
        .frame(height: 50)
        .padding(.horizontal, 4)
    }

    private var vehicleChips: some View {
        HStack(spacing: 6) {
            chip(icon: "bolt.fill",       label: "EV only", on: $evOnly)
            chip(icon: "car.fill",        label: "Sedan",   on: $sedan)
            chip(icon: "car.2.fill",      label: "SUV",     on: $suv)
            chip(icon: "person.2.fill",   label: "≤4 seats", on: $smallSeats)
        }
    }

    private func chip(icon: String, label: String, on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(label).font(.system(size: 11, weight: .heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(on.wrappedValue ? VPalette.primary : VPalette.textSec)
            .background(on.wrappedValue ? VPalette.primaryContainer : VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on.wrappedValue ? VPalette.primary : VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var driverPrefs: some View {
        VStack(spacing: 0) {
            prefRow(title: "Verified drivers only", subtitle: "MyKad + license check", on: $verifiedOnly)
            divider()
            prefRow(title: "≥4.8 star rating", subtitle: "Filter low-rated drivers", on: $minRating)
            divider()
            prefRow(title: "Same-gender driver", subtitle: "Optional safety preference", on: $sameGender)
            divider()
            prefRow(title: "Speaks Malay", subtitle: "Driver language preference", on: $malayLanguage)
        }
        .background(VPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func prefRow(title: String, subtitle: String, on: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                Text(subtitle).font(.system(size: 11)).foregroundColor(VPalette.textSec)
            }
            Spacer()
            VToggle(isOn: on)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func divider() -> some View {
        Rectangle().fill(VPalette.border).frame(height: 1)
    }
}
