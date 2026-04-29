//
// Flavia study app
//
// Onboarding step that explains why Flavia needs background location access
// (UV, air quality, pollen captured around the user as they move) and
// triggers the system "Always" permission prompt. iOS shows a three-option
// alert (Allow Always / While Using / Don't Allow) — whatever the user
// picks, the flow continues. Granting Always lets the app refresh
// environment data via significant-change events even when closed; lesser
// grants still allow foreground refreshes on sign-in.
//

import CoreLocation
import SpeziOnboarding
import SpeziViews
import SwiftUI


struct LocationPermissions: View {
    @Environment(LocationProvider.self) private var locationProvider
    @Environment(EnvironmentRefresh.self) private var environmentRefresh
    @Environment(ManagedNavigationStack.Path.self) private var managedNavigationPath

    @State private var processing = false


    var body: some View {
        OnboardingView(
            content: {
                VStack {
                    OnboardingTitleView(
                        title: "Location Access",
                        subtitle: "Used for UV, air quality, and pollen."
                    )
                    Spacer()
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 150))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                    Text(
                        "Flavia uses your approximate location to look up UV, air quality, and pollen around you, "
                        + "and saves each reading with the time and place it was taken. "
                        + "Choose \u{201C}Allow Always\u{201D} so Flavia can refresh in the background as you move; "
                        + "\u{201C}While Using\u{201D} works too, but readings will only update when you open the app."
                    )
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
                    Spacer()
                }
            },
            footer: {
                OnboardingActionsView(
                    primaryTitle: "Share Location",
                    primaryAction: {
                        await grantAndAdvance()
                    },
                    secondaryTitle: "Not Now",
                    secondaryAction: {
                        managedNavigationPath.nextStep()
                    }
                )
            }
        )
        .navigationBarBackButtonHidden(processing)
        .navigationTitle(Text(verbatim: ""))
        .toolbar(.visible)
    }


    private func grantAndAdvance() async {
        processing = true
        let status = await locationProvider.requestAlwaysAuthorization()
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            await environmentRefresh.refresh(force: true)
        }
        processing = false
        managedNavigationPath.nextStep()
    }
}


#Preview {
    ManagedNavigationStack {
        LocationPermissions()
    }
    .previewWith(standard: TemplateApplicationStandard()) {
        LocationProvider()
        EnvironmentRefresh()
    }
}
