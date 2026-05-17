import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: RewardStore
    @State private var title = ""
    @State private var points = 1
    @State private var taskBeingEdited: RewardTask?
    @State private var editedTitle = ""
    @State private var editedPoints = 1
    @State private var editedRecurrence: RewardTask.Recurrence = .none

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(
                        eyebrow: "Chore catalog",
                        title: "Work",
                        subtitle: "Reusable chores that show up on every kid's screen."
                    )

                    addWorkCard
                    configuredWorkSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 42)
                .padding(.bottom, 20)
            }

            if taskBeingEdited != nil {
                EditTaskModal(
                    title: $editedTitle,
                    points: $editedPoints,
                    recurrence: $editedRecurrence,
                    onCancel: {
                        taskBeingEdited = nil
                        editedTitle = ""
                        editedPoints = 1
                        editedRecurrence = .none
                    },
                    onSave: {
                        if let taskBeingEdited {
                            store.updateTask(taskBeingEdited, title: editedTitle, points: editedPoints)
                            store.updateTaskRecurrence(taskBeingEdited, recurrence: editedRecurrence)
                        }
                        taskBeingEdited = nil
                        editedTitle = ""
                        editedPoints = 1
                        editedRecurrence = .none
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .kidCoinBackground()
        .animation(.easeOut(duration: 0.18), value: taskBeingEdited)
    }

    private var addWorkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Add Work")

            TextField("Mow the lawn", text: $title)
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

            PillButton(
                title: "Add Work",
                systemImage: "plus",
                tone: .primary,
                disabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                store.addTask(title: title, points: points)
                title = ""
                points = 1
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
                            Spacer()
                            Text("+\(task.points)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(KidCoinTheme.primary)
                            Button {
                                taskBeingEdited = task
                                editedTitle = task.title
                                editedPoints = task.points
                                editedRecurrence = task.recurrence
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(KidCoinTheme.primary)
                                    .frame(width: 38, height: 38)
                                    .background(KidCoinTheme.primary.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit \(task.title)")
                            Button {
                                store.deleteTask(task)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(KidCoinTheme.destructive)
                                    .frame(width: 38, height: 38)
                                    .background(KidCoinTheme.destructive.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(task.title)")
                        }
                        .padding(14)
                        .tileCard(cornerRadius: 20)
                    }
                }
            }
        }
    }
}

private struct EditTaskModal: View {
    @Binding var title: String
    @Binding var points: Int
    @Binding var recurrence: RewardTask.Recurrence
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

                Picker("Repeats", selection: $recurrence) {
                    ForEach(RewardTask.Recurrence.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

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
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(maxWidth: 360)
            .tileCard(cornerRadius: 28)
            .padding(.horizontal, 24)
        }
    }
}
