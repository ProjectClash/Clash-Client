import ClashClientUI
import SwiftUI

 
 
 
 
 
struct ClashMacCoreRefusalSheet: View {
    let issue: ClashHomeConnectionIssue
     
     
     
     
    var onDemandPausedNote: ClashDisplayText? = nil
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(clash: .copy("Can’t Connect"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            Form {
                ClashCoreRefusalAccount(issue: issue)
                 
                 
                 
                if let onDemandPausedNote {
                    Section {
                        Text(clash: onDemandPausedNote)
                            .font(.subheadline)
                            .accessibilityIdentifier("connection.issue.on-demand-paused")
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(ClashCopy.key("Done")) { onDone() }
                    .buttonStyle(.borderedProminent)
                     
                     
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("home.refusal.done")
            }
            .padding(20)
        }
         
         
        .frame(width: 520, height: 400)
         
         
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.refusal")
        .onExitCommand(perform: onDone)
    }
}
