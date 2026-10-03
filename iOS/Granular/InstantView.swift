import GranularCore
import PhotosUI
import SwiftUI

struct InstantView: View {
    @Environment(Darkroom.self) private var darkroom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The job currently sitting in the gate. It stays there for a beat after
    /// finishing so the exposure reads before the film advances.
    @State private var exposure: Exposure?
    /// Film position in frames, animated from -1 to 0 each time the film winds on.
    @State private var advance: CGFloat = 0
    @State private var isAdvancing = false
    /// How many frames have been wound on, so the edge numbers travel with the film.
    @State private var framesWound = 0
    /// Film loading, played once as the app opens.
    @State private var isCanisterSeated = false
    @State private var filmOut: CGFloat = 0
    @State private var isPicking = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: Lightbox?

    private struct Lightbox {
        let frame: ExposedFrame
        /// Where the negative sits on screen, so the print can develop from it.
        let origin: CGRect
    }

    private struct Exposure: Equatable {
        let jobID: UUID
        let startedAt: Date
    }

    private struct LeadJobKey: Equatable {
        let id: UUID?
        let state: Darkroom.Job.State?
    }

    var body: some View {
        VStack(spacing: 0) {
            FilmChamber(
                style: CanisterStyle(recipe: darkroom.currentRecipe, isModified: darkroom.isRecipeModified),
                recipeName: darkroom.recipeDisplayName,
                gate: exposure.map { exposure in
                    let isSpoiled = if case .failed = darkroom.jobs.first(where: { $0.id == exposure.jobID })?.state { true } else { false }
                    return GateExposure(id: exposure.jobID, image: darkroom.thumbnails[exposure.jobID], isSpoiled: isSpoiled)
                },
                frames: exposedFrames,
                advance: advance,
                isAdvancing: isAdvancing,
                framesWound: framesWound,
                isCanisterSeated: isCanisterSeated,
                filmOut: filmOut,
                reduceMotion: reduceMotion,
                onChoose: { isPicking = true },
                onOpen: { frame, origin in viewing = Lightbox(frame: frame, origin: origin) },
                onRetry: { darkroom.retry($0) }
            ) { tin in
                RecipeMenu { tin }
            }
            .padding(.horizontal, 14)

            FilmBackStatusBar()
        }
        .photosPicker(
            isPresented: $isPicking,
            selection: $picked,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            darkroom.develop(items)
            picked = []
        }
        .overlay {
            if let viewing, let url = viewing.frame.outputURL {
                FrameViewer(url: url, negative: viewing.frame.image, origin: viewing.origin) {
                    self.viewing = nil
                }
                .transition(.identity)
            }
        }
        .onChange(of: LeadJobKey(id: darkroom.jobs.first?.id, state: darkroom.jobs.first?.state)) { _, _ in
            leadJobChanged()
        }
        .onChange(of: darkroom.exposures) { _, exposures in
            // A frame saved from Edit mode moves the count on without the film.
            if darkroom.batch == nil, exposure == nil, !isAdvancing {
                framesWound = exposures
            }
        }
        .onAppear {
            framesWound = darkroom.exposures
            loadFilm()
        }
    }

    /// The canister drops into its pocket, then the film pulls out across the gate.
    private func loadFilm() {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) {
                isCanisterSeated = true
                filmOut = 1
            }
            return
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.14).delay(0.15)) {
            isCanisterSeated = true
        }
        withAnimation(.smooth(duration: 0.6).delay(0.3)) {
            filmOut = 1
        }
    }

    private var exposedFrames: [ExposedFrame] {
        darkroom.jobs.compactMap { job -> ExposedFrame? in
            guard job.id != exposure?.jobID else { return nil }
            let development: ExposedFrame.Development
            switch job.state {
            case .finished(let outputURL): development = .developed(outputURL)
            case .failed(let message): development = .spoiled(message)
            case .processing: return nil
            }
            return ExposedFrame(
                id: job.id,
                image: darkroom.thumbnails[job.id],
                development: development,
                isUnsaved: job.isUnsaved
            )
        }
        .prefix(4)
        .map { $0 }
    }

    private func leadJobChanged() {
        guard let job = darkroom.jobs.first else { return }
        switch job.state {
        case .processing:
            guard exposure?.jobID != job.id else { return }
            withAnimation(.spring(duration: 0.55)) {
                exposure = Exposure(jobID: job.id, startedAt: .now)
            }
        case .finished, .failed:
            // A spoiled frame fogs in the gate, then winds on like any other.
            advanceFilm(after: job.id)
        }
    }

    private func advanceFilm(after jobID: UUID) {
        guard let exposure, exposure.jobID == jobID else { return }
        let hold = reduceMotion ? 0.4 : 1.6
        let remaining = hold - Date.now.timeIntervalSince(exposure.startedAt)
        Task {
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard self.exposure?.jobID == jobID else { return }
            windOn()
        }
    }

    /// Winds the film on one frame: the exposed frame moves out of the gate
    /// and the whole strip, perforations and edge print included, travels with it.
    private func windOn() {
        var jump = Transaction()
        jump.disablesAnimations = true
        withTransaction(jump) {
            exposure = nil
            advance = -1
            isAdvancing = true
            framesWound += 1
        }
        Task {
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.9)) {
                advance = 0
            } completion: {
                isAdvancing = false
                darkroom.filmDidSettle()
            }
        }
    }
}

// MARK: - Status bar

private struct FilmBackStatusBar: View {
    @Environment(Darkroom.self) private var darkroom

    var body: some View {
        HStack(spacing: 12) {
            // Progress shows on the film itself; only a failure needs words.
            if case .failed(let message) = darkroom.jobs.first?.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            // Frames that couldn't go into the library.
            if darkroom.unsavedCount > 0 {
                Button {
                    darkroom.saveUnsaved()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save \(darkroom.unsavedCount)")
                            .fontWeight(.medium)
                    }
                    .engraved()
                }
                .accessibilityLabel("Save \(darkroom.unsavedCount) to Photos")
            }

            Spacer(minLength: 12)

            // A lone image needs no count; a batch reads off “3 of 12”.
            if let batch = darkroom.batch, batch.total > 1 {
                Text("\(batch.position) of \(batch.total)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: batch.position)
                    .engraved()
                    .transition(.opacity)
                    .accessibilityLabel("Processing image \(batch.position) of \(batch.total)")
            }

            HStack(spacing: 6) {
                Text("EXP")
                    .font(.system(size: 10, weight: .bold).width(.condensed))
                    .tracking(2.4)
                    .engraved()
                Text(String(format: "%02d", darkroom.exposures))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(FilmBackPalette.counter)
                    .shadow(color: FilmBackPalette.counter.opacity(0.55), radius: 4)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 42, minHeight: 26)
                    .background(CounterWindow())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: darkroom.exposures)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(darkroom.exposures) photos developed")
        }
        .animation(.easeOut(duration: 0.2), value: (darkroom.batch?.total ?? 0) > 1)
        .font(.footnote)
        .padding(.horizontal, 20)
        .frame(height: 52)
    }
}
