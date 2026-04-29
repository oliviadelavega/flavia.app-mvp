//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

@_spi(TestingSupport) import SpeziAccount
import SwiftUI


struct HomeView: View {
    enum Tabs: String {
        case symptoms
        case meals
        case overview
    }


    @AppStorage(StorageKeys.homeTabSelection) private var selectedTab = Tabs.symptoms
    @AppStorage(StorageKeys.tabViewCustomization) private var tabViewCustomization = TabViewCustomization()

    @Environment(Account.self) private var account: Account?
    @Environment(EnvironmentRefresh.self) private var environmentRefresh
    @Environment(SymptomReminderScheduler.self) private var reminders

    @State private var presentingAccount = false


    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Symptoms", systemImage: "heart.text.square", value: .symptoms) {
                SymptomLogView(presentingAccount: $presentingAccount)
            }
            .customizationID("home.symptoms")
            Tab("Meals", systemImage: "fork.knife", value: .meals) {
                MealLogView(presentingAccount: $presentingAccount)
            }
            .customizationID("home.meals")
            Tab("Overview", systemImage: "calendar", value: .overview) {
                OverviewView(presentingAccount: $presentingAccount)
            }
            .customizationID("home.overview")
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($tabViewCustomization)
        .sheet(isPresented: $presentingAccount) {
            AccountSheet(dismissAfterSignIn: false) // presentation was user initiated, do not automatically dismiss
        }
        .accountRequired(!FeatureFlags.disableFirebase && !FeatureFlags.skipOnboarding) {
            AccountSheet()
        }
        .task(id: account?.details?.accountId) {
            guard account?.details != nil else {
                return
            }
            await environmentRefresh.refresh()
            await reminders.ensureRollingWindow()
        }
    }
}


#Preview {
    var details = AccountDetails()
    details.userId = "lelandstanford@stanford.edu"
    details.name = PersonNameComponents(givenName: "Leland", familyName: "Stanford")
    
    return HomeView()
        .previewWith(standard: TemplateApplicationStandard()) {
            AccountConfiguration(service: InMemoryAccountService(), activeDetails: details)
            LocationProvider()
            EnvironmentRefresh()
            SymptomReminderScheduler()
        }
}
