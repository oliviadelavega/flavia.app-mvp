//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziOnboarding
import SpeziViews
import SwiftUI


struct InterestingModules: View {
    @Environment(ManagedNavigationStack.Path.self) private var managedNavigationPath
    
    
    var body: some View {
        SequentialOnboardingView(
            title: "Flavia",
            subtitle: "DATA_OVERVIEW_SUBTITLE",
            steps: [
                SequentialOnboardingView.Step(
                    title: "Daily Symptoms",
                    description: "DATA_OVERVIEW_AREA1_DESCRIPTION"
                ),
                SequentialOnboardingView.Step(
                    title: "Meals",
                    description: "DATA_OVERVIEW_AREA2_DESCRIPTION"
                ),
                SequentialOnboardingView.Step(
                    title: "Wearables & Vitals",
                    description: "DATA_OVERVIEW_AREA3_DESCRIPTION"
                ),
                SequentialOnboardingView.Step(
                    title: "Environment",
                    description: "DATA_OVERVIEW_AREA4_DESCRIPTION"
                )
            ],
            actionText: "Next",
            action: {
                managedNavigationPath.nextStep()
            }
        )
    }
}


#Preview {
    ManagedNavigationStack {
        InterestingModules()
    }
}
