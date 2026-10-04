"""LoRA fine-tune of Gemma 3 270M for symptom extraction, then merge.

    .venv/bin/python make_dataset.py
    .venv/bin/python train.py            # ~10-20 min on a 4 GB laptop GPU
    ./convert.sh                         # -> health-extractor-270m-q8_0.gguf

Fits in 4 GB VRAM (bf16 weights + LoRA adapters).
"""

import json
import os

import torch
from peft import LoraConfig, get_peft_model
from torch.utils.data import DataLoader
from transformers import AutoModelForCausalLM, AutoTokenizer, get_cosine_schedule_with_warmup

BASE = "unsloth/gemma-3-270m-it"  # ungated mirror of google/gemma-3-270m-it
OUT = "out/merged"
# Must equal LlmExtraction.finetunedPrompt (health_core) — a Dart test pins it.
FINETUNED_PROMPT = "Extract symptoms from this health worker note as JSON.\nNote: {note}"
MAX_LEN = 192
EPOCHS = 2
BATCH = 4
ACCUM = 4  # effective batch 16; Gemma's 262k vocab makes logits big on 4 GB
LR = 2e-4

device = "cuda" if torch.cuda.is_available() else "cpu"
dtype = torch.bfloat16 if device == "cuda" and torch.cuda.is_bf16_supported() else torch.float32

tok = AutoTokenizer.from_pretrained(BASE)
model = AutoModelForCausalLM.from_pretrained(BASE, torch_dtype=dtype, attn_implementation="eager").to(device)
model = get_peft_model(model, LoraConfig(
    r=32, lora_alpha=64, lora_dropout=0.05, task_type="CAUSAL_LM",
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
))
model.print_trainable_parameters()


def prompt_ids(note):
    msgs = [{"role": "user", "content": FINETUNED_PROMPT.format(note=note)}]
    text = tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False)
    return tok(text, add_special_tokens=False)["input_ids"]  # template already has <bos>


def encode(row):
    p = prompt_ids(row["note"])
    t = tok(row["target"] + "<end_of_turn>\n", add_special_tokens=False)["input_ids"]
    ids = (p + t)[:MAX_LEN]
    labels = ([-100] * len(p) + t)[:MAX_LEN]  # learn only the JSON answer
    return ids, labels


def load(path):
    return [json.loads(l) for l in open(path, encoding="utf-8")]


train_rows, val_rows = load("train.jsonl"), load("val.jsonl")
train = [encode(r) for r in train_rows]


def collate(batch):
    n = max(len(i) for i, _ in batch)
    pad = tok.pad_token_id
    ids = torch.tensor([i + [pad] * (n - len(i)) for i, _ in batch])
    labels = torch.tensor([l + [-100] * (n - len(l)) for _, l in batch])
    mask = torch.tensor([[1] * len(i) + [0] * (n - len(i)) for i, _ in batch])
    return ids, labels, mask


loader = DataLoader(train, batch_size=BATCH, shuffle=True, collate_fn=collate)
opt = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=LR, weight_decay=0.0)
steps = EPOCHS * len(loader) // ACCUM
sched = get_cosine_schedule_with_warmup(opt, int(0.05 * steps), steps)

model.train()
step = 0
for epoch in range(EPOCHS):
    for i, (ids, labels, mask) in enumerate(loader):
        out = model(input_ids=ids.to(device), attention_mask=mask.to(device), labels=labels.to(device))
        (out.loss / ACCUM).backward()
        if (i + 1) % ACCUM:
            continue
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step(); sched.step(); opt.zero_grad()
        step += 1
        if step % 50 == 0:
            print(f"epoch {epoch} step {step}/{steps} loss {out.loss.item():.4f}", flush=True)


@torch.no_grad()
def predict(note):
    ids = torch.tensor([prompt_ids(note)]).to(device)
    gen = model.generate(ids, max_new_tokens=64, do_sample=False,
                         eos_token_id=tok.convert_tokens_to_ids("<end_of_turn>"))
    return tok.decode(gen[0, ids.shape[1]:], skip_special_tokens=True).strip()


model.eval()
sample = val_rows[:150]
exact = 0
for r in sample:
    got = predict(r["note"])
    try:
        ok = json.loads(got) == json.loads(r["target"])
    except json.JSONDecodeError:
        ok = False
    exact += ok
print(f"val exact match: {exact}/{len(sample)} = {exact / len(sample):.1%}")

merged = model.merge_and_unload()
os.makedirs(OUT, exist_ok=True)
merged.save_pretrained(OUT, safe_serialization=True)
tok.save_pretrained(OUT)
# llama.cpp's Gemma converter needs the SentencePiece file, which
# save_pretrained doesn't write.
import shutil
from huggingface_hub import hf_hub_download
target = f"{OUT}/tokenizer.model"
if os.path.exists(target):
    os.remove(target)  # a previous copy may be read-only (HF cache perms)
shutil.copyfile(hf_hub_download(BASE, "tokenizer.model"), target)
print("saved", OUT)
