# Flavia — Setup

This is the [Stanford Spezi Template Application](https://github.com/StanfordSpezi/SpeziTemplateApplication) rebranded to **Flavia** with email/password auth, HealthKit collection, questionnaires, consent, and image + audio upload to Firebase Cloud Storage.

## What's already wired up

- **Auth**: `SpeziFirebaseAccount` — email/password + Sign in with Apple, configured in `TemplateApplication/TemplateApplicationDelegate.swift`.
- **Database**: Firestore via `SpeziFirestore`. Per-user data goes to `users/{accountId}/...`. Rules in `firebase/firestore.rules`.
- **Storage**: Firebase Cloud Storage via `SpeziFirebaseStorage`. Per-user buckets at `users/{accountId}/...`. Rules in `firebase/firebasestorage.rules`.
- **HealthKit**: step count + heart rate samples uploaded automatically (see `TemplateApplicationStandard.swift`).
- **Consent**: PDF stored at `users/{accountId}/consent/{timestamp}.pdf`.
- **Images & audio** (added for Flavia): `TemplateApplicationStandard.storeImage(_:)` and `storeAudio(at:)` upload to `users/{accountId}/images/` and `users/{accountId}/audio/` — see `TemplateApplication/Media/MediaUpload.swift`.

## One-time setup

### 1. Apple Developer / Xcode
1. Open `TemplateApplication.xcodeproj` in Xcode 16 or later.
2. Select the `TemplateApplication` target → Signing & Capabilities → set your **Team**.
   The bundle identifier is currently `com.flavia.app` — change it if you don't own that namespace.
3. (Optional) Rename the Xcode target/scheme/folder from `TemplateApplication` to `Flavia` via Xcode's refactor (right-click target → Rename). Doing this in Xcode is much safer than editing `project.pbxproj` by hand.

### 2. Firebase project
1. Create a Firebase project at https://console.firebase.google.com.
2. Add an iOS app with bundle ID `com.flavia.app` (or whatever you set above).
3. Download the generated `GoogleService-Info.plist` and replace the placeholder at:
   `TemplateApplication/Supporting Files/GoogleService-Info.plist`
4. In the Firebase console, enable:
   - **Authentication** → Email/Password (and Apple if you want Sign in with Apple).
   - **Firestore Database** (Native mode).
   - **Cloud Storage**.

### 3. Deploy security rules
From the repo root, with the [Firebase CLI](https://firebase.google.com/docs/cli) installed:
```bash
firebase login
firebase use --add        # select your project
firebase deploy --only firestore:rules,storage
```
The rules in `firebase/firestore.rules` and `firebase/firebasestorage.rules` already restrict reads/writes to `users/{uid}/...` for the matching authenticated user — this is the "RLS-equivalent" you asked for.

### 4. Run
- Press ⌘R in Xcode to run on simulator or device.
- Sign-in defaults to the live Firebase project. To run against the local emulator suite instead, pass `--useFirebaseEmulator` as a launch argument and `firebase emulators:start` from `firebase/`.

## How to upload an image / audio clip from a SwiftUI view

```swift
@Environment(TemplateApplicationStandard.self) private var standard

// image picked from UIImagePickerController / PhotosPicker
let jpeg = uiImage.jpegData(compressionQuality: 0.9)!
try await standard.storeImage(jpeg)

// audio recorded via AVAudioRecorder to a temp .m4a file
try await standard.storeAudio(at: recordingURL)
```

## Customization checklist for your study

- [ ] `TemplateApplication/Resources/ConsentDocument.md` — replace placeholder consent with IRB-approved text.
- [ ] `TemplateApplication/Resources/SocialSupportQuestionnaire.json` — swap for your study's FHIR questionnaire (or add more).
- [ ] `TemplateApplication/Onboarding/Welcome.swift` + welcome copy in `Localizable.xcstrings` (search for `WELCOME_*`).
- [ ] `TemplateApplication/TemplateApplicationDelegate.swift` — add/remove `CollectSamples(...)` for the HealthKit types your study needs.
- [ ] App icon at `TemplateApplication/Resources/Spezi Icon.icon` (rename and replace).

## What's NOT yet built (intentionally)

- A UI for capturing photos / recording audio. The `storeImage` / `storeAudio` APIs are wired up but you'll need to add a SwiftUI screen (e.g. with `PhotosPicker` + `AVAudioRecorder`) that calls them. This is study-specific.
- Push notifications / FCM — `SpeziNotifications` is configured for local notifications only.
- Background HealthKit delivery rules — defaults are fine for most studies; tune in the `HealthKit { ... }` block.
