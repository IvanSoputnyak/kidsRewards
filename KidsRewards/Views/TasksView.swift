import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: RewardStore
    @State private var title = ""
    @State private var points = 1

    var body: some View {
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
        .kidCoinBackground()
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
                            Spacer()
                            Text("+\(task.points)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(KidCoinTheme.primary)
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
                        }
                        .padding(14)
                        .tileCard(cornerRadius: 20)
                    }
                }
            }
        }
    }
}
