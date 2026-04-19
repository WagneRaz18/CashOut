import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "EntryView")

struct EntryView: View {
    // ViewModel is owned by ContentView so it survives iOS 26 `Tab` API content-closure
    // re-evaluation on selection change. Owning `viewModel` locally as `@State` caused
    // the ViewModel (and all in-progress entry state) to be destroyed on every tab
    // switch because the value-based `Tab` API re-evaluates its content closure when
    // `selectedTab` changes, tearing down `@State` storage.
    @Bindable var viewModel: ExpenseEntryViewModel
    var onSaveComplete: (@MainActor @Sendable () -> Void)? = nil

    @State private var showingNoteSheet = false
    @State private var saveTask: Task<Void, Never>?
    @State private var retryTask: Task<Void, Never>?
    @State private var saveTrigger: Int = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(SemanticColor.error)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
            }

            Spacer(minLength: 0)

            AmountDisplayView(amount: viewModel.amountInSatang)
                .padding(.horizontal, Spacing.lg)

            Button {
                showingNoteSheet = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: viewModel.noteText.isEmpty ? "square.and.pencil" : "note.text")
                        .font(.subheadline)
                    Text(viewModel.noteText.isEmpty ? "Add note" : viewModel.noteText)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .foregroundStyle(SemanticColor.onSurfaceVariant)
            }
            .buttonStyle(.plain)
            .padding(.bottom, Spacing.sm)
            .accessibilityLabel(viewModel.noteText.isEmpty ? "Add note" : "Edit note")

            Spacer(minLength: 0)

            if viewModel.categoryLoadFailed {
                Button {
                    logger.info("Category retry tapped")
                    retryTask?.cancel()
                    retryTask = Task { await viewModel.retryLoadCategories() }
                } label: {
                    Label("Categories unavailable — tap to retry", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(SemanticColor.error)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry loading categories")
                .accessibilityHint("Loads the category list again")
                .padding(.vertical, Spacing.sm)
            } else {
                CategoryPickerView(
                    categories: viewModel.categories,
                    selectedCategoryID: viewModel.selectedCategoryID,
                    onSelect: { viewModel.selectCategory($0) }
                )
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }

            NumpadView(
                onDigit: { viewModel.appendDigit($0) },
                onBackspace: { viewModel.deleteLastDigit() }
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.sm)

            SaveButtonView(
                isDisabled: viewModel.isAmountZero || viewModel.isSaving || viewModel.selectedCategoryID == nil,
                onSave: {
                    logger.info("Save button tapped — amount=\(viewModel.amountInBaht, privacy: .private) Baht")
                    let tapStart = CFAbsoluteTimeGetCurrent()

                    // Immediate: animation + haptic (optimistic, same frame as tap)
                    saveTrigger += 1
                    HapticService.shared.trigger(.saveTap)

                    saveTask?.cancel()
                    saveTask = Task {
                        // Save runs in parallel with animation
                        async let save: Void = viewModel.saveExpense()

                        // Wait for animation to complete
                        do {
                            try await Task.sleep(for: .milliseconds(900))
                        } catch { return }
                        guard !Task.isCancelled else { return }

                        await save
                        guard !Task.isCancelled else { return }
                        guard viewModel.saveError == nil else {
                            logger.warning("Save failed after animation — error: \(viewModel.saveError ?? "unknown", privacy: .public)")
                            return
                        }

                        let tapElapsed = (CFAbsoluteTimeGetCurrent() - tapStart) * 1000
                        logger.info("Save success — navigating — \(tapElapsed, format: .fixed(precision: 1))ms since tap")
                        UIAccessibility.post(notification: .announcement, argument: "Expense saved")
                        onSaveComplete?()
                        viewModel.resetForm()
                    }
                }
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)
        }
        .overlay {
            SaveConfirmationOverlay(trigger: saveTrigger)
        }
        .background {
            Surface.base.ignoresSafeArea()

            if !reduceTransparency {
                // Ambient atmospheric glow — matches mockup
                ZStack {
                    Circle()
                        .fill(SemanticColor.primary.opacity(0.10))
                        .blur(radius: 120)
                        .frame(width: 400, height: 280)
                        .offset(x: 120, y: -80)

                    Circle()
                        .fill(SemanticColor.tertiary.opacity(0.05))
                        .blur(radius: 100)
                        .frame(width: 340, height: 210)
                        .offset(x: -100, y: 300)
                }
                .drawingGroup()
                .allowsHitTesting(false)
            }
        }
        .task {
            logger.debug("EntryView.task: loading categories")
            await viewModel.loadCategories()
        }
        .onAppear {
            viewModel.refreshCategoryOrder()
        }
        .sheet(isPresented: $showingNoteSheet) {
            NoteEntrySheet(noteText: $viewModel.noteText)
                .presentationDetents([.large])
        }
        .onDisappear {
            logger.debug("EntryView.onDisappear — cancelling tasks")
            saveTask?.cancel()
            retryTask?.cancel()
            // Share tasks are owned by ExpenseRepository and must NOT be cancelled here:
            // a successful save dismisses EntryView, which would race-cancel the in-flight
            // CloudKit share and silently drop the expense from the partner's shared zone.
        }
    }
}

// Previews are isolated from the live SQLite/CloudKit stack via PersistenceController.preview
// (in-memory). Data-layer repos are fresh instances against the in-memory store. Service-layer
// defaults (auth, haptic, categoryOrderStore) use .shared since they do not touch Core Data.
#Preview {
    EntryView(viewModel: ExpenseEntryViewModel(
        expenseRepository: ExpenseRepository(persistence: .preview),
        categoryRepository: CategoryRepository(persistence: .preview)
    ))
}

#Preview("Dynamic Type — AX3") {
    EntryView(viewModel: ExpenseEntryViewModel(
        expenseRepository: ExpenseRepository(persistence: .preview),
        categoryRepository: CategoryRepository(persistence: .preview)
    ))
    .dynamicTypeSize(.accessibility3)
}
