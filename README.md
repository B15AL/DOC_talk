# Small AI Health Assistant

An offline helper for community health workers. On an Android smartphone it
works fully offline. Feature phones use it over SMS. It **suggests** next steps
and never diagnoses; the health worker always makes the final decision.

```
health_core/          Shared pure-Dart logic: questions, WHO-IMCI-style rules,
                      Hindi/English text, keyword + AI extraction, SMS format
health_ai_assistant/  Flutter Android app (offline, voice, history, optional AI model)
sms_server/           SMS webhook server + terminal simulator for feature phones
tools/llm_eval/       Desktop benchmark of on-device models (same runtime and prompt as the app)
tools/finetune/       Synthetic data + LoRA fine-tune of Gemma 3 270M -> GGUF
```

## Run it

```bash
# Android app (phone connected with USB debugging, or an emulator)
cd health_ai_assistant
flutter pub get
flutter run                       # or: flutter build apk --release

# Feature-phone demo without any SMS provider
cd sms_server && dart pub get && dart run bin/simulate.dart

# Tests
cd health_core && dart test
cd health_ai_assistant && flutter test
cd sms_server && dart test
```

## App features
- Choose the language (Hindi/English); every screen and question is translated.
- Describe the patient by **voice or text**. Symptoms are understood by keywords,
  plus the optional **on-device AI model**.
- **The worker confirms what was understood** before any question is skipped.
- One-tap Yes / No / Not sure questions, read aloud, with an undo button. Danger
  signs are asked first.
- Result: 🟢 routine / 🟠 clinician review / 🔴 urgent referral, with the reason
  behind each suggestion and a disclaimer.
- Nothing is saved until the worker confirms. A **history** screen lists past
  consultations.
- Send a short summary with no patient name by SMS (`HAI1 …`). The server decodes it.

## On-device AI ("Smart AI")
The model is **Gemma 3 270M, fine-tuned for this app** (`tools/finetune`): a
~280 MB GGUF that runs offline through llama.cpp (`llamadart`) in about 0.5 s
per note. General-purpose 0.5–1B models were benchmarked first
(`tools/llm_eval`) and added more wrong findings than right ones, so they are
not used.

Home screen → Smart AI card → *Import model file*, or *Download* if the app was
built with `--dart-define=AI_MODEL_URL=...`. The model only **pre-fills the
form**. Its output is limited to the allowed fields, checked again in
`health_core`, and **confirmed by the worker**. Rules and referrals never come
from the AI. If the model is missing, too slow, or the phone is 32-bit, the app
falls back to keyword matching.

## Before real-world use
Have a clinician review every rule and translation. Get consent. Encrypt
stored data. Test on real low-end phones.
