# Fine-tuning the on-device symptom extractor

General-purpose small models (Qwen3 0.6B, Qwen2.5 0.5B, Gemma 3 1B) were
benchmarked with `tools/llm_eval` and did badly on this task: 1–3 out of 10
correct, and more wrong additions than right ones. So we fine-tune **Gemma 3
270M** on exactly this task. The result is a ~280 MB GGUF that runs in about
0.5 s per note on CPU.

```bash
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python torch --index-url https://download.pytorch.org/whl/cu126
uv pip install --python .venv/bin/python "transformers>=4.56" peft accelerate datasets sentencepiece protobuf gguf numpy safetensors

.venv/bin/python make_dataset.py   # 9,000 synthetic notes (Hindi / Hinglish / English)
.venv/bin/python train.py          # LoRA, ~15 min on a 4 GB laptop GPU (RTX 2050)
./convert.sh                       # -> health-extractor-270m-q8_0.gguf

# Honest check, using the same runtime and prompt as the app:
cd ../llm_eval && dart run bin/eval.dart ../finetune/health-extractor-270m-q8_0.gguf finetuned fresh
```

No GPU? Run the same scripts on a free Colab T4 notebook.

## How the data works
`make_dataset.py` builds notes from symptom phrases, durations, negations
("bukhar nahi hai"), code-mixing, blood mentioned somewhere other than the
stool, and distractor symptoms we never extract (headache, vomiting, …). The
label is known by construction. Every sentence in the eval tool is excluded
(`held_out_notes.json`).

**Best next improvement:** add 200–500 *real* anonymised notes written by
health workers, labelled by hand. Synthetic data teaches the format; real data
teaches how people actually write.

## Adding a symptom
1. Add the question to `health_core` (`LocalAIService.questionBank`, rules, strings).
2. Add its phrases to `SYMPTOMS` in `make_dataset.py` and its key to `_target`.
3. Retrain, convert, re-run the eval.

## Getting the model onto phones
- **No internet (field use):** copy the `.gguf` to the phone (USB, Bluetooth, SD
  card), then in the app go to Smart AI → *Import model file*. During
  development you can push it over USB:
  `adb push health-extractor-270m-q8_0.gguf /sdcard/Download/`
- **Download inside the app:** upload the file (for example
  `huggingface-cli upload <you>/health-extractor health-extractor-270m-q8_0.gguf`),
  then build with
  `flutter build apk --dart-define=AI_MODEL_URL=https://huggingface.co/<you>/health-extractor/resolve/main/health-extractor-270m-q8_0.gguf`

The model only pre-fills the form. The app constrains its output to the allowed
fields, validates it again, and asks the health worker to confirm before any
question is skipped.
