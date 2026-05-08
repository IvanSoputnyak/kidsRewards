import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var store: RewardStore
    @State private var title = ""
    @State private var points = 1

    var body: some View {
        NavigationStack {
            List {
                Section("Add Work") {
                    TextField("Work name", text: $title)
                    Stepper("\(points) points", value: $points, in: 1...100)
                    Button {
                        store.addTask(title: title, points: points)
                        title = ""
                        points = 1
                    } label: {
                        Label("Add Work", systemImage: "plus.circle.fill")
                    }
                }

                Section("Configured Work") {
                    ForEach(store.state.tasks) { task in
                        HStack {
                            Text(task.title)
                            Spacer()
                            Text("\(task.points) points")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { store.state.tasks[$0] }.forEach(store.deleteTask)
                    }
                }
            }
            .navigationTitle("Work")
        }
    }
}
