
# Small AI Health Assistant (DOC_talk)

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
