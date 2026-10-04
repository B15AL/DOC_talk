"""Generates synthetic training notes for the symptom extractor.

Each note is assembled from Hindi / Hinglish / English building blocks, so
the correct JSON label is known by construction. Output: train.jsonl, val.jsonl
with {"note": ..., "target": "<compact JSON>"}.

The prompt and label format must match LlmExtraction.finetunedPrompt in
health_core/lib/src/llm_extraction.dart.
"""

import json
import random

random.seed(7)

LANGS = ["hinglish", "hindi", "english"]

SYMPTOMS = {
    "fever": {
        "hinglish": ["bukhar", "tez bukhar", "halka bukhar", "bukhaar", "badan garam", "bukhar aur thand"],
        "hindi": ["बुखार", "तेज़ बुखार", "हल्का बुखार", "बदन गरम", "ज्वर", "तेज बुखार"],
        "english": ["fever", "high fever", "mild fever", "temperature", "a fever", "body feels hot"],
    },
    "cough": {
        "hinglish": ["khansi", "sukhi khansi", "balgam wali khansi", "khaansi", "lagatar khansi"],
        "hindi": ["खांसी", "खाँसी", "सूखी खांसी", "बलगम वाली खांसी", "लगातार खाँसी"],
        "english": ["cough", "dry cough", "a cough", "wet cough", "coughing"],
    },
    "diarrhea": {
        "hinglish": ["dast", "loose motion", "patli tatti", "pet chal raha", "paani jaisi tatti", "baar baar latrine"],
        "hindi": ["दस्त", "पतले दस्त", "पतली टट्टी", "बार बार दस्त", "पानी जैसे दस्त"],
        "english": ["diarrhoea", "diarrhea", "loose motions", "watery stools", "loose stools"],
    },
    "blood_in_stool": {
        "hinglish": ["tatti mein khoon", "potty mein khoon", "dast mein khoon"],
        "hindi": ["मल में खून", "टट्टी में खून", "दस्त में खून"],
        "english": ["blood in the stool", "bloody stools", "blood in stools"],
    },
}

# Symptoms we never extract; teach the model to ignore them.
DISTRACTORS = {
    "hinglish": ["sir dard", "ulti", "kamzori", "pet dard", "chakkar", "badan dard", "zukaam", "bhookh nahi lagti", "daane"],
    "hindi": ["सिर दर्द", "उल्टी", "कमज़ोरी", "पेट दर्द", "चक्कर", "बदन दर्द", "जुकाम", "भूख नहीं लगती"],
    "english": ["headache", "vomiting", "weakness", "stomach pain", "dizziness", "body ache", "a cold", "a rash", "no appetite"],
}

# Blood that is NOT in the stool — must not become blood_in_stool.
OTHER_BLOOD = {
    "hinglish": ["balgam mein khoon", "naak se khoon", "ulti mein khoon", "thook mein khoon"],
    "hindi": ["बलगम में खून", "नाक से खून", "उल्टी में खून"],
    "english": ["blood in the phlegm", "nosebleed", "blood in vomit", "blood when spitting"],
}

NO_BLOOD = {
    "hinglish": ["khoon nahi hai", "khoon nahi aa raha", "tatti mein khoon nahi"],
    "hindi": ["खून नहीं है", "खून नहीं आ रहा", "मल में खून नहीं"],
    "english": ["no blood", "no blood in stool", "stool has no blood"],
}

NUM_WORDS = {
    "hinglish": {1: "ek", 2: "do", 3: "teen", 4: "char", 5: "paanch", 6: "chhe", 7: "saat", 10: "das", 15: "pandrah", 20: "bees"},
    "hindi": {1: "एक", 2: "दो", 3: "तीन", 4: "चार", 5: "पाँच", 6: "छह", 7: "सात", 10: "दस", 15: "पंद्रह", 20: "बीस"},
    "english": {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 10: "ten", 15: "fifteen", 20: "twenty"},
}

UNITS = {
    "hinglish": {"day": ["din"], "week": ["hafte", "hafta"], "month": ["mahine", "mahina"]},
    "hindi": {"day": ["दिन"], "week": ["हफ्ते", "हफ़्ते"], "month": ["महीने"]},
    "english": {"day": ["days", "day"], "week": ["weeks", "week"], "month": ["months", "month"]},
}

PHRASES = {  # duration phrase -> days
    "hinglish": {"kal se": 1, "aaj subah se": 1, "parso se": 2, "pichle hafte se": 7, "ek hafte se": 7, "ek mahine se": 30, "kaafi dino se": None},
    "hindi": {"कल से": 1, "आज सुबह से": 1, "परसों से": 2, "पिछले हफ्ते से": 7, "एक महीने से": 30, "काफ़ी दिनों से": None},
    "english": {"since yesterday": 1, "since this morning": 1, "since last week": 7, "for a week": 7, "for a month": 30, "for a while": None},
}

SUBJECTS = {
    "hinglish": ["", "baccha ko ", "bachche ko ", "mareez ko ", "patient ko ", "meri beti ko ", "isko ", "dadi ko "],
    "hindi": ["", "बच्चे को ", "मरीज़ को ", "मुझे ", "उसको ", "बच्ची को ", "माँ को "],
    "english": ["", "patient has ", "child has ", "my son has ", "she has ", "he has "],
}

NEGATIONS = {
    "hinglish": ["{s} nahi hai", "{s} nahi", "{s} bilkul nahi hai", "koi {s} nahi"],
    "hindi": ["{s} नहीं है", "{s} नहीं", "कोई {s} नहीं है"],
    "english": ["no {s}", "does not have {s}", "{s} is not there", "denies {s}"],
}

JOINERS = {
    "hinglish": [" aur ", ", ", " saath mein ", ", aur "],
    "hindi": [" और ", ", ", " साथ में "],
    "english": [" and ", ", ", " with "],
}


def bucket(symptom, days):
    if days is None:
        return None
    if symptom == "fever":
        return "d_1_2" if days <= 2 else ("d_3_6" if days <= 6 else "d_7_plus")
    if symptom == "cough":
        return "c_lt_14" if days < 14 else "c_14_plus"
    return None


def duration(lang):
    """Returns (text, days or None)."""
    if random.random() < 0.3:
        text, days = random.choice(list(PHRASES[lang].items()))
        return text, days
    unit = random.choices(["day", "week", "month"], weights=[6, 3, 1])[0]
    n = random.choice([1, 2, 3, 4, 5, 6, 7, 10, 15, 20] if unit == "day" else [1, 2, 3, 4])
    days = n * {"day": 1, "week": 7, "month": 30}[unit]
    num = str(n) if random.random() < 0.5 else NUM_WORDS[lang].get(n, str(n))
    u = random.choice(UNITS[lang][unit])
    if lang == "english":
        return random.choice([f"for {num} {u}", f"for the last {num} {u}", f"{num} {u}"]), days
    if lang == "hindi":
        return f"{num} {u} से", days
    return random.choice([f"{num} {u} se", f"pichle {num} {u} se"]), days


def clause(lang, phrase, dur):
    if dur is None:
        forms = {
            "hinglish": ["{s} hai", "{s} ho raha hai", "{s}", "{s} bhi hai"],
            "hindi": ["{s} है", "{s} हो रहा है", "{s}"],
            "english": ["{s}", "has {s}", "{s} present"],
        }[lang]
        return random.choice(forms).format(s=phrase)
    forms = {
        "hinglish": ["{d} {s} hai", "{s} {d}", "{d} {s} ho raha hai", "{s} hai {d}"],
        "hindi": ["{d} {s} है", "{s} {d}", "{s} है {d}"],
        "english": ["{s} {d}", "{s} {d}", "has had {s} {d}"],
    }[lang]
    return random.choice(forms).format(s=phrase, d=dur)


def make_negation_note(lang):
    """Only denials plus maybe a distractor: "no fever, no loose motions, only X"."""
    denied = random.sample(["fever", "cough", "diarrhea"], k=random.choice([1, 2, 3]))
    parts = [random.choice(NEGATIONS[lang]).format(s=random.choice(SYMPTOMS[d][lang])) for d in denied]
    if random.random() < 0.8:
        only = {"hinglish": "sirf ", "hindi": "सिर्फ़ ", "english": "only "}[lang]
        parts.append(only + random.choice(DISTRACTORS[lang] + OTHER_BLOOD[lang]))
    return random.choice(SUBJECTS[lang]) + random.choice([", ", "; "] + JOINERS[lang]).join(parts), {}


def make_shared_duration_note(lang):
    """One duration for two symptoms: "3 din se bukhar aur khansi hai"."""
    a, b = "fever", "cough"
    dur, days = duration(lang)
    while days is None:
        dur, days = duration(lang)
    sa, sb = random.choice(SYMPTOMS[a][lang]), random.choice(SYMPTOMS[b][lang])
    if random.random() < 0.5:
        sa, sb = sb, sa
    joiner = {"hinglish": " aur ", "hindi": " और ", "english": " and "}[lang]
    tail = {"hinglish": " hai", "hindi": " है", "english": ""}[lang]
    if lang == "english":
        note = f"{sa}{joiner}{sb} {dur}"
    else:
        note = f"{dur} {sa}{joiner}{sb}{tail}"
    label = {a: "yes", b: "yes"}
    for sym in (a, b):
        bk = bucket(sym, days)
        if bk:
            label[f"{sym}_days"] = bk
    return random.choice(SUBJECTS[lang]) + note, label


def make_note():
    lang = random.choice(LANGS)
    r = random.random()
    if r < 0.12:
        note, label = make_negation_note(lang)
        return note, _target(label)
    if r < 0.20:
        note, label = make_shared_duration_note(lang)
        return note, _target(label)
    present = random.sample(["fever", "cough", "diarrhea"], k=random.choices([0, 1, 2, 3], weights=[1, 5, 4, 1])[0])
    if "diarrhea" in present and random.random() < 0.3:
        present.append("blood_in_stool")
    no_blood = "diarrhea" in present and "blood_in_stool" not in present and random.random() < 0.25
    absent = [s for s in ["fever", "cough", "diarrhea"] if s not in present]

    parts, label = [], {}
    for s in present:
        # Code-mixing: Hinglish notes often use English symptom words.
        vocab_lang = "english" if lang == "hinglish" and random.random() < 0.2 else lang
        phrase = random.choice(SYMPTOMS[s][vocab_lang])
        dur_text, days = (None, None)
        if s in ("fever", "cough") and random.random() < 0.6:
            dur_text, days = duration(lang)
        parts.append(clause(lang, phrase, dur_text))
        label[s] = "yes"
        b = bucket(s, days)
        if b:
            label[f"{s}_days"] = b
    if absent and random.random() < 0.35:
        neg = random.choice(absent)
        parts.append(random.choice(NEGATIONS[lang]).format(s=random.choice(SYMPTOMS[neg][lang])))
    if no_blood:
        parts.append(random.choice(NO_BLOOD[lang]))
    if random.random() < 0.12:
        parts.append(random.choice(OTHER_BLOOD[lang]))
    if random.random() < 0.5 or not parts:
        parts.append(random.choice(DISTRACTORS[lang]) + {"hinglish": " hai", "hindi": " है", "english": ""}[lang])
    random.shuffle(parts)

    note = random.choice(SUBJECTS[lang]) + random.choice(JOINERS[lang]).join(parts)
    if random.random() < 0.3:
        note = note.capitalize() if lang == "english" else note
    return note, _target(label)


def _target(label):
    order = ["fever", "fever_days", "cough", "cough_days", "diarrhea", "blood_in_stool"]
    return json.dumps({k: label[k] for k in order if k in label}, ensure_ascii=False, separators=(",", ":"))


def main():
    held_out = set(json.load(open("held_out_notes.json", encoding="utf-8")))
    seen, rows = set(), []
    while len(rows) < 9300:
        note, target = make_note()
        if note in seen or note in held_out:
            continue
        seen.add(note)
        rows.append({"note": note, "target": target})
    with open("train.jsonl", "w", encoding="utf-8") as f:
        for r in rows[:9000]:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    with open("val.jsonl", "w", encoding="utf-8") as f:
        for r in rows[9000:]:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    for r in rows[:8]:
        print(r["note"], "->", r["target"])


if __name__ == "__main__":
    main()
