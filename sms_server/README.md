# SMS server (feature-phone mode)

Runs the **same triage rules** as the Android app (`../health_core`), one
question per SMS, answered by number.

```
dart pub get
dart run bin/simulate.dart     # chat in the terminal, no gateway needed (demo)
dart run bin/server.dart       # HTTP server on $PORT (default 8080)
dart test
```

## Conversation
1. First SMS = free description in Hindi/Hinglish/English, e.g. `3 din se bukhar hai`.
   Language is detected (Devanagari or Hinglish words → Hindi, else English) and
   symptoms mentioned are pre-filled.
2. Server asks the remaining questions: `1=Yes 2=No 3=Not sure` (words like
   `haan` / `nahi` also work). Danger sign = yes → stops and sends URGENT referral.
3. Final SMS: triage level, top 3 suggestions, disclaimer.
4. `0` restarts, `HINDI` / `ENGLISH` switches language. Sessions expire after 30 min.
5. Reports from the app (`HAI1 ...`) are decoded and stored separately.

Finished consultations go to `$DATA_DIR/sms_consultations.jsonl`, app reports to
`app_reports.jsonl`. Phone numbers are masked to the last 4 digits.

## Connecting a real SMS number
| Endpoint | Use with |
|---|---|
| `POST /sms/incoming` `{"from","text"}` → `{"replies":[...]}` | Android phone running an SMS-gateway app (cheapest for a pilot — a ₹10/day SIM), MSG91, Gupshup; write a tiny adapter if the field names differ |
| `POST /sms/twilio` | Twilio "A message comes in" webhook (returns TwiML) |

For a local demo, expose the server with a tunnel (e.g. `cloudflared tunnel --url http://localhost:8080`).

## Before real use
- Sessions are in memory: use Redis/DB if you run more than one instance.
- Hindi SMS are Unicode (70 chars per segment), so the final message is ~4–6 segments — budget for it.
- Store data encrypted, get consent, and have a clinician review all rules and text.
