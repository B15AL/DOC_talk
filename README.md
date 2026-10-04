
# Small AI Health Assistant (DOC_talk)
# here is my website link 
   Click [here to visit my website](https://bishaldoctalk.lovable.app/).


**Offline-first AI helper for community health workers in rural areas.**

Works fully offline on Android smartphones.  
Feature phones use it over SMS.  

It **suggests** next steps and possible referrals — it never diagnoses.  
The final decision always stays with the human health worker.

> “This is only a suggestion. Please confirm with a clinician.”  
> (Yeh sirf sujhav hai. Antim faisla aapka hai.)

---

## How it works

**Primary user**: Community Health Worker (ASHA / ANM)  
**Secondary user**: Patient (can also use it)

1. Health worker describes what they see/hear in the local language (voice or text).
2. AI organizes the information, fills a simple structured form, and suggests possible things to check + referral options.
3. Health worker confirms everything before anything is saved.
4. Strong disclaimer is always shown.

---

## Dual Mode Architecture

### Mode 1: Android Smartphone (100% Offline)

1. **First Install / Setup**
   - App asks: “Apni bhasha chunein” (Choose your language)
   - User selects language (Hindi / English — more languages later)
   - App downloads the matching small language pack + quantized model
   - After this, everything works offline

2. **Normal Use (Fully Offline)**
   - User speaks or types in the chosen language
   - Local AI asks structured Yes/No/Not sure questions
   - Generates clean Symptom Summary
   - Shows safe next-step + referral suggestions with color coding:
     - 🟢 Routine
     - 🟠 Clinician review recommended
     - 🔴 Urgent referral
   - Strong disclaimer always shown
   - Health worker confirms → saves locally (History screen)

3. **Optional Background Sync**
   - When signal is available → sends compressed summary via SMS to Server AI
   - Server can improve future suggestions (no patient name is ever sent)

### Mode 2: Feature Phone (SMS)

1. User sends SMS in any language  
   Example:  
   - “I have fever for 3 days and cough”  
   - “मुझे तीन दिन से बुखार है”

2. Server AI (with Auto-Translate)
   - Detects language
   - Translates to internal working language
   - Runs the same structured questioning logic
   - Translates questions back to user’s language
   - Sends Yes/No style SMS questions

3. After answers, Server sends:
   - Clean symptom summary (in user’s language)
   - Safe suggestions + possible referral
   - Clear disclaimer

4. No AI model runs on the feature phone.

---

## Project Structure

health_core/          Shared pure-Dart logic: questions, WHO-IMCI-style rules,
Hindi/English text, keyword + AI extraction, SMS format
health_ai_assistant/  Flutter Android app (offline, voice, history, optional AI model)
sms_server/           SMS webhook server + terminal simulator for feature phones
tools/llm_eval/       Desktop benchmark of on-device models
tools/finetune/       Synthetic data + LoRA fine-tune of Gemma 3 270M → GGUF



---

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


# Install the APK
cd health_ai_assistant/build/app/outputs/flutter-apk/
# Install: app-arm64-v8a-release.apk

# Install the custom AI model
cd tools/finetune
# Install the .gguf file: health-extractor-270m-q8_0.gguf


## Before real-world use

Have a clinician review every rule and translation
Get proper consent
Encrypt stored data
Test thoroughly on real low-end phones
