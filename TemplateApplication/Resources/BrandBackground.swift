//
// Flavia study app
//
// Hides the default scrolling-form background and paints `brandIvory`
// behind the rows. Used on the three feature tabs (Symptoms, Meals,
// Overview) so the app reads as warm neutral rather than system gray.
//

import SwiftUI


extension View {
    func brandIvoryBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.brandIvory.ignoresSafeArea())
    }
}
