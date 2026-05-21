import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: RewardStore
    @State private var title = ""
    @State private var points = 1
    @State private var addRecurrence: RewardTask.Recurrence = .none
    @State private var addAssignedKidIDs: Set<UUID> = []
    @State private var taskBeingEdited: RewardTask?
    @State private var editedTitle = ""
    @State private var editedPoints = 1
    @State private var editedRecurrence: RewardTask.Recurrence = .none
    @State private var editedAssignedKidIDs: Set<UUID> = []

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(
                        eyebrow: "Chore catalog",
                        title: "Work",
                        subtitle: "Assign chores to everyone or selected kids. They appear on each kid's award screen."
                    )

                    addWorkCard
                    configuredWorkSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 42)
            }
            .kidCoinScroll()

            if taskBeingEdited != nil {
                EditTaskModal(
                    title: $editedTitle,
                    points: $editedPoints,
                    recurrence: $editedRecurrence,
                    assignedKidIDs: $editedAssignedKidIDs,
                    kids: store.state.kids,
                    onCancel: {
                        withAnimation(KidCoinMotion.modal) {
                            taskBeingEdited = nil
                        }
                        editedTitle = ""
                        editedPoints = 1
                        editedRecurrence = .none
                        editedAssignedKidIDs = []
                    },
                    onSave: {
                        if let taskBeingEdited {
                            withAnimation(KidCoinMotion.list) {
                                store.updateTask(
                                    taskBeingEdited,
                                    title: editedTitle,
                                    points: editedPoints,
                                    recurrence: editedRecurrence,
                                    assignedKidIDs: Array(editedAssignedKidIDs)
                                )
                            }
                        }
                        withAnimation(KidCoinMotion.modal) {
                            taskBeingEdited = nil
                        }
                        editedTitle = ""
                        editedPoints = 1
                        editedRecurrence = .none
                        editedAssignedKidIDs = []
                    }
                )
                .transition(.kidCoinModal)
            }
        }
        .kidCoinBackground()
        .animation(KidCoinMotion.modal, value: taskBeingEdited)
    }

    private var addWorkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Add Work")

            TextField("Mow the lawn", text: $title)
                .kidCoinNameEntry()
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(KidCoinTheme.muted)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Text("Points")
                    .font(.subheadline)
                    .foregroundStyle(KidCoinTheme.mutedText)
                Spacer()
                CounterControl(value: $points, range: 1...100)
            }

            SegmentedPickerRow(
                selection: $addRecurrence,
                items: RewardTask.Recurrence.allCases,
                label: \.label
            )

            KidAssignmentPicker(kids: store.state.kids, selectedKidIDs: $addAssignedKidIDs)

            PillButton(
                title: "Add Work",
                systemImage: "plus",
                tone: .primary,
                disabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                withAnimation(KidCoinMotion.list) {
                    store.addTask(
                        title: title,
                        points: points,
                        recurrence: addRecurrence,
                        assignedKidIDs: Array(addAssignedKidIDs)
                    )
                }
                title = ""
                points = 1
                addRecurrence = .none
                addAssignedKidIDs = []
            }
        }
        .padding(18)
        .tileCard(cornerRadius: 26)
    }

    private var configuredWorkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Configured Work")
            if store.state.tasks.isEmpty {
                EmptyStatePanel(
                    systemImage: "checklist",
                    title: "No chores yet",
                    message: "Add one above so kids can start earning."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(store.state.tasks) { task in
                        HStack(spacing: 12) {
                            Text(task.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if task.recurrence != .none {
                                Text(task.recurrence.label)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KidCoinTheme.mintText)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(KidCoinTheme.mint.opacity(0.24))
                                    .clipShape(Capsule())
                            }
                            Text(assignmentLabel(for: task))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(KidCoinTheme.primary)
                            Spacer()
                            Text("+\(task.points)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(KidCoinTheme.primary)
                            Button {
                                withAnimation(KidCoinMotion.modal) {
                                    taskBeingEdited = task
                                }
                                editedTitle = task.title
                                editedPoints = task.points
                                editedRecurrence = task.recurrence
                                editedAssignedKidIDs = Set(task.assignedKidIDs)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(KidCoinTheme.primary)
                                    .frame(width: 38, height: 38)
                                    .background(KidCoinTheme.primary.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(KidCoinPressButtonStyle(scale: 0.94))
                            .accessibilityLabel("Edit \(task.title)")
                            Button {
                                withAnimation(KidCoinMotion.list) {
                                    store.deleteTask(task)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(KidCoinTheme.destructive)
                                    .frame(width: 38, height: 38)
                                    .background(KidCoinTheme.destructive.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(KidCoinPressButtonStyle(scale: 0.94))
                            .accessibilityLabel("Delete \(task.title)")
                        }
                        .padding(14)
                        .tileCard(cornerRadius: 20)
                        .transition(.kidCoinRow)
                    }
                }
                .animation(KidCoinMotion.list, value: store.state.tasks)
            }
        }
    }

    private func assignmentLabel(for task: RewardTask) -> String {
        if task.assignedKidIDs.isEmpty {
            return "Everyone"
        }
        let names = store.state.kids
            .filter { task.assignedKidIDs.contains($0.id) }
            .map(\.name)
        if names.count == 1 { return names[0] }
        return "\(names.count) kids"
    }
}

private enum ChoreAssignmentScope: String, CaseIterable, Identifiable {
    case everyone
    case selectedKids

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyone:
            return "Everyone"
        case .selectedKids:
            return "Selected"
        }
    }
}

private struct KidAssignmentPicker: View {
    let kids: [Kid]
    @Binding var selectedKidIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who can earn this?")
                .font(.subheadline.weight(.semibold))

            if kids.isEmpty {
                Text("Add a kid on the Kids tab first. Until then, new chores apply to everyone.")
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
            } else {
                SegmentedPickerRow(
                    selection: assignmentScopeBinding,
                    items: ChoreAssignmentScope.allCases,
                    label: \.label
                )
                .accessibilityLabel("Who can earn this chore")

                Text(scopeHint)
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                if assignmentScope == .selectedKids {
                    VStack(spacing: 6) {
                        ForEach(kids) { kid in
                            Toggle(kid.name, isOn: binding(for: kid.id))
                                .toggleStyle(.switch)
                                .tint(KidCoinTheme.primary)
                        }
                    }
                    .padding(.top, 4)

                    if selectedKidIDs.isEmpty {
                        Text("Select at least one kid, or switch to Everyone.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KidCoinTheme.destructive)
                    }
                }
            }
        }
    }

    private var assignmentScope: ChoreAssignmentScope {
        selectedKidIDs.isEmpty ? .everyone : .selectedKids
    }

    private var assignmentScopeBinding: Binding<ChoreAssignmentScope> {
        Binding(
            get: { assignmentScope },
            set: { scope in
                switch scope {
                case .everyone:
                    selectedKidIDs = []
                case .selectedKids:
                    if selectedKidIDs.isEmpty {
                        selectedKidIDs = Set(kids.map(\.id))
                    }
                }
            }
        )
    }

    private var scopeHint: String {
        switch assignmentScope {
        case .everyone:
            return "Any kid in the family can earn this, including kids you add later."
        case .selectedKids:
            return "Only the kids you turn on below will see this chore."
        }
    }

    private func binding(for kidID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedKidIDs.contains(kidID) },
            set: { isOn in
                if isOn {
                    selectedKidIDs.insert(kidID)
                } else {
                    selectedKidIDs.remove(kidID)
                }
            }
        )
    }
}

private struct EditTaskModal: View {
    @Binding var title: String
    @Binding var points: Int
    @Binding var recurrence: RewardTask.Recurrence
    @Binding var assignedKidIDs: Set<UUID>
    let kids: [Kid]
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            KidCoinTheme.foreground.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                Text("Edit Work")
                    .font(.system(.title2, design: .rounded).weight(.bold))

                TextField("Work name", text: $title)
                    .kidCoinNameEntry()
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    Text("Points")
                        .font(.subheadline)
                        .foregroundStyle(KidCoinTheme.mutedText)
                    Spacer()
                    CounterControl(value: $points, range: 1...100)
                }

                SegmentedPickerRow(
                    selection: $recurrence,
                    items: RewardTask.Recurrence.allCases,
                    label: \.label
                )

                KidAssignmentPicker(kids: kids, selectedKidIDs: $assignedKidIDs)

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.muted)
                        .clipShape(Capsule())

                    Button("Save") {
                        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onSave()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
            }
            .padding(22)
            .frame(maxWidth: 360)
            .tileCard(cornerRadius: 28)
            .padding(.horizontal, 24)
        }
    }
}
