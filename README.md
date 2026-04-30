<!--

This source file is part of the Flavia study app, built on the Stanford Spezi Template Application.

SPDX-FileCopyrightText: 2023 Stanford University

SPDX-License-Identifier: MIT

-->

# Flavia

Flavia is an iOS study app for tracking eczema and the lifestyle and environmental factors that may aggravate it. It is built on the [Stanford Spezi](https://github.com/StanfordSpezi/Spezi) ecosystem on top of the [Spezi Template Application](https://github.com/StanfordSpezi/SpeziTemplateApplication), and uses Firebase / Firestore for per-user storage.

The app captures three streams of data per participant:

1. **Daily symptom check-ins** — eczema severity, itch, stress, period status, affected body parts, topicals used, and free-form notes.
2. **Meal entries** — what was eaten, when, and which eczema-relevant tags apply (dairy, gluten, egg, nut, etc.).
3. **Ambient environment snapshots** — location, weather, UV index, air quality, and pollen, pulled from [Open-Meteo](https://open-meteo.com) at the participant's coordinate.

Together these let the study team correlate eczema flares with diet and environmental exposure over time.

## Features

### Symptoms tab
A daily check-in form. Each calendar day produces a single document at `users/{uid}/symptomLogs/{YYYY-MM-DD}` (upserted, last-write-wins). Captures:

- Eczema severity, itch level, and stress level on a 0–5 scale
- Whether the participant is on their period (yes / no / skip)
- A multi-select of affected body parts (hands, inner elbows, behind knees, face, …)
- A multi-select of topicals used (moisturizer, cortisone, prescription cream, …)
- Free-form notes

### Meals tab
A meal entry form that writes one document per meal under `users/{uid}/meals/{autoId}`. Captures a description, the time the meal was eaten, and tags from a fixed eczema-relevant vocabulary.

The form has two AI affordances that run **entirely on-device** via Apple's `FoundationModels` framework (iOS 26+, Apple Intelligence-capable hardware):

- **Dictate** — speak the meal description; Apple's speech recognizer transcribes it.
- **Polish & tag** — runs the on-device LLM to clean up dictation errors (e.g. "k-mall" → "kale") and propose tags from the allowed vocabulary. Auto-fires when dictation stops, and is also available as a manual button. On unsupported devices these affordances are hidden and the user falls back to typing + the manual chip selector.

No meal text leaves the device for these helpers.

### Overview tab
A 14-day rollup that groups each day's symptom check-in and meal entries together, with "Today" / "Yesterday" / dated section headers. Pull-to-refresh re-fetches from Firestore.

### Environmental snapshots
A background pipeline (`Environment/`) combines Core Location with Open-Meteo's forecast, air-quality, and pollen endpoints. Each refresh writes a history document at `users/{uid}/environment/{YYYY-MM-DD-HHmm}` and mirrors the latest reading into `users/{uid}/environment/current`. Snapshots include:

- Location (lat/long, accuracy, timezone)
- Temperature, apparent temperature, humidity, precipitation
- UV index (current, clear-sky, daily max)
- Air quality (European AQI, US AQI, PM2.5, PM10, CO, NO₂, SO₂, ozone)
- Pollen (alder, birch, grass, mugwort, olive, ragweed — European stations only)

### Daily reminders
A local-notification scheduler (`Reminders/SymptomReminderScheduler.swift`) maintains a rolling 7-day window of one-shot reminders at 8 PM local time, one per calendar day, with stable identifiers (`symptom-reminder-YYYY-MM-DD`). Saving today's check-in cancels today's pending reminder so participants aren't nudged for work they already did.

### Onboarding
A Spezi onboarding flow walks the user through:

- Welcome screen and module overview
- Consent signature
- Account creation (Firebase Auth)
- HealthKit access (granular per-type)
- Location permission (used for environment snapshots)
- Notification permission (used for the daily check-in reminder)

## Getting started

See [SETUP.md](SETUP.md) for prerequisites (Xcode, Firebase project configuration, signing) and steps to build and run the app.

The app targets iOS 18+; the on-device meal-polish feature requires iOS 26+ and Apple Intelligence-capable hardware. Without it, meal logging works fine — the AI button is simply hidden.

## Project structure

```
TemplateApplication/
├── Symptoms/        Daily check-in form, model, Firestore storage
├── Meals/           Meal entry form, dictation, on-device tag suggester
├── Overview/        14-day rollup view
├── Environment/     Location + Open-Meteo snapshot pipeline
├── Reminders/       Local-notification scheduler for the daily nudge
├── Onboarding/      Welcome, consent, permissions, account flow
├── Account/         Account sheet + button (Spezi Account)
├── Firestore/       Firestore configuration
└── ...
```

## Contributing

Contributions are welcome. Please read the upstream Spezi [contribution guidelines](https://github.com/StanfordSpezi/.github/blob/main/CONTRIBUTING.md) and [code of conduct](https://github.com/StanfordSpezi/.github/blob/main/CODE_OF_CONDUCT.md) first.

This project is based on the [Stanford Spezi Template Application](https://github.com/StanfordSpezi/SpeziTemplateApplication), which itself builds on the [Stanford Biodesign Digital Health Template Application](https://github.com/StanfordBDHG/TemplateApplication) and [ContinuousDelivery Example by Paul Schmiedmayer](https://github.com/PSchmiedmayer/ContinousDelivery), all provided under the MIT license.

## License

This project is licensed under the MIT License. See [Licenses](LICENSES) for more information.

![Spezi Footer](https://raw.githubusercontent.com/StanfordSpezi/.github/main/assets/FooterLight.png#gh-light-mode-only)
![Spezi Footer](https://raw.githubusercontent.com/StanfordSpezi/.github/main/assets/FooterDark.png#gh-dark-mode-only)
