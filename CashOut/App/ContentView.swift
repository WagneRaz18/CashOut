import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("CashOut")
    }
}

#Preview {
    ContentView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
}
