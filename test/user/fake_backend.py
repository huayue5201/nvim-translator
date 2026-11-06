#!/usr/bin/env python3
import sys, json, time, os
argv = sys.argv[1:]
log = os.environ.get("FAKE_LOG")
if log:
    with open(log, "a") as f:
        f.write("START %s\n" % " ".join(argv))
stream = "--stream" in argv
batch = "--batch" in argv
delay = float(os.environ.get("SLOW_DELAY", "3"))
stagger = float(os.environ.get("SLOW_STAGGER", "0"))
engines = ["fake"]
for i, e in enumerate(argv):
    if e == "--engines":
        engines = argv[i+1].split(",")
input_text = sys.stdin.read()
texts = [t for t in input_text.split("\n") if t.strip()] if (batch or "--stdin" in argv) else [argv[-1]]
if batch:
    time.sleep(delay)
    for i, t in enumerate(texts):
        print(json.dumps({"id": i, "text": t, "results": [{"engine": e, "sl": "en", "tl": "zh", "text": "T:" + t, "phonetic": "", "paraphrase": "T:" + t, "explains": []} for e in engines]}), flush=True)
        if stagger: time.sleep(stagger)
elif stream:
    time.sleep(delay)
    for t in texts:
        for e in engines:
            print(json.dumps({"engine": e, "sl": "en", "tl": "zh", "text": "T:" + t, "phonetic": "", "paraphrase": "T:" + t, "explains": []}), flush=True)
            if stagger: time.sleep(stagger)
    print(json.dumps({"done": True}), flush=True)
else:
    time.sleep(delay)
    t = texts[0]
    print(json.dumps({"text": t, "status": 1, "results": [{"engine": e, "sl": "en", "tl": "zh", "text": "T:" + t, "phonetic": "", "paraphrase": "T:" + t, "explains": []} for e in engines]}))
