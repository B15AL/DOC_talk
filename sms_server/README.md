# Health AI server (SMS + app)

One server for both channels, running the **same rules** (`../health_core`)
and the **same fine-tuned AI model** as the Android app.

```bash
dart pub get
dart test

# Demo without any SMS provider (add MODEL_PATH to use the AI)
MODEL_PATH=../tools/finetune/health-extractor-270m-q8_0.gguf dart run bin/simulate.dart

# Server
MODEL_PATH=../tools/finetune/health-extractor-270m-q8_0.gguf \
API_KEY=choose-a-secret PORT=8080 dart run bin/server.dart
```

| Env | Meaning |
|---|---|
| `MODEL_PATH` | fine-tuned `.gguf`. Without it the server uses keyword matching only |
| `API_KEY` | required `x-api-key` header for `/api/*` (the app). Set it! |
| `PORT`, `DATA_DIR` | default `8080`, `./data` |

## Endpoints
**Feature phones (SMS gateways):**
- `POST /sms/incoming` `{"from","text"}` → `{"replies":[...]}`
- `POST /sms/twilio` (Twilio webhook, replies with TwiML)

**Android app** (`x-api-key` header):
- `GET /api/status` → `{"ai": true}`
- `POST /api/understand` `{"text"}` → `{"findings":{...},"aiOnly":[...]}`. Used by
  phones that don't have the model on the device.
- `POST /api/consultations` (Consultation JSON). Saved consultations are uploaded here.

## Connecting the app
In the app: Smart AI → **Online server**. Enter the server address and the API
key, then tap **Save & test**.
- Same Wi-Fi: `http://<laptop-ip>:8080` (find the IP with `ip addr`)
- Internet: `cloudflared tunnel --url http://localhost:8080` and use the https address

## Connecting a real SMS number (Twilio)
Use the tunnel address + `/sms/twilio` as the number's "A message comes in" webhook (POST).

## SMS conversation
1. First SMS = description in Hindi/Hinglish/English (`3 din se bukhar hai`). The
   language is detected, and the AI + keywords pre-fill what was said.
2. Questions come one per SMS, answered by number or in words. The order and
   the added checks follow what was understood, the same as in the app. A
   danger sign stops the questions and sends an URGENT referral.
3. The final SMS has the triage level, the top advice and a disclaimer. `0`
   restarts, and `HINDI` / `ENGLISH` switches language.

Data is saved in `data/*.jsonl`, with phone numbers masked. Before real use:
add a database with encryption, get consent, and have a clinician review all
rules and text.
