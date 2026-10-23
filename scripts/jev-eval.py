#!/usr/bin/env python3
"""Replay eval cases through the vision model with a prompt variant, and score it against the ideal answers.

Cases come from `ScreenJournal cases --out DIR --apply`: one folder per session with request.json (as sent,
image removed), reply.json and screen.jpg. Ideals are graded JSONL lines ({"id", "ideal": {work, automatable, task},
"confidence"}). A variant is a JSON file merged over each request:

    {"name": "with-about",
     "about": "I build AI products…",                 # replaces state.about_the_person
     "model": "typesafe-ai/jev-1.14.0",
     "questions": {"work": {"instructions": "…"}},    # any field of any question
     "image": false}                                   # text only, as the text model is asked

    scripts/jev-eval.py --cases ~/ScreenJournal/evals/jev-1.14.0 \
        --ideals ~/ScreenJournal/evals/jev-1.14.0-review/graded-*.jsonl \
        --variant variant.json [--baseline] [--min-confidence medium] [--out results.jsonl]

--baseline scores the replies already in the cases instead of calling the model.
The key is read from AI_GATEWAY_API_KEY by name and never printed.
"""
import argparse, base64, concurrent.futures as futures, glob, json, os, sys, time, urllib.request, urllib.error

URL = "https://ai-gateway.vercel.sh/typesafe/v1/systemone"
CONFIDENCE = {"low": 0, "medium": 1, "high": 2}


def merge(base, over):
    for key, value in over.items():
        base[key] = merge(base.get(key, {}), value) if isinstance(value, dict) and isinstance(base.get(key), dict) else value
    return base


def request_for(case_dir, variant):
    request = json.load(open(os.path.join(case_dir, "request.json")))
    if "about" in variant:
        request["state"]["about_the_person"] = variant["about"]
    if "model" in variant:
        request["model"] = variant["model"]
    merge(request.setdefault("questions", {}), variant.get("questions", {}))
    if variant.get("image") is False:
        request["state"].pop("screenshot", None)
        return request
    jpeg = open(os.path.join(case_dir, "screen.jpg"), "rb").read()
    request["assets"] = {"screen": {"type": "image", "data_base64": base64.b64encode(jpeg).decode(), "format": "jpeg"}}
    return request


def send(request, key):
    body = json.dumps(request).encode()
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    if "assets" in request:
        headers["TypeSafe-Danger-Zone-Images"] = "true"
    for attempt in range(3):
        if attempt:
            time.sleep(2 ** attempt)
        req = urllib.request.Request(URL, data=body, method="POST", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code < 500 and error.code != 429:
                return {"error": f"{error.code} {error.read()[:200].decode(errors='replace')}"}
        except Exception:  # timeouts and resets are retried
            pass
    return {"error": "no reply"}


def answers(reply, steps):
    a = reply.get("answers") or {}
    try:
        return {"work": a["work"]["noul"], "automatable": a["automatable"]["score"] * 3 / (steps - 1), "task": a["task"]["choice"]}
    except (KeyError, TypeError):
        return None


def score(rows):
    """Task accuracy, mean absolute error on work (0–1) and automatable (0–3), and the share within the rubric's thresholds."""
    n = len(rows)
    if not n:
        return {}
    task = sum(r["got"]["task"] == r["ideal"]["task"] for r in rows) / n
    work = sum(abs(r["got"]["work"] - r["ideal"]["work"]) for r in rows) / n
    auto = sum(abs(r["got"]["automatable"] - r["ideal"]["automatable"]) for r in rows) / n
    allright = sum(r["got"]["task"] == r["ideal"]["task"] and abs(r["got"]["work"] - r["ideal"]["work"]) < 0.3
                   and abs(r["got"]["automatable"] - r["ideal"]["automatable"]) < 1 for r in rows) / n
    return {"cases": n, "task_accuracy": round(task, 3), "work_mae": round(work, 3), "automatable_mae": round(auto, 3), "all_three_right": round(allright, 3)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cases", required=True)
    parser.add_argument("--ideals", required=True, nargs="+")
    parser.add_argument("--variant")
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--min-confidence", default="medium", choices=CONFIDENCE)
    parser.add_argument("--out")
    args = parser.parse_args()

    ideals = {}
    for path in [p for pattern in args.ideals for p in glob.glob(os.path.expanduser(pattern))]:
        for line in open(path):
            if line.strip():
                row = json.loads(line)
                if CONFIDENCE.get(row.get("confidence"), 0) >= CONFIDENCE[args.min_confidence]:
                    ideals[row["id"]] = row["ideal"]
    cases = os.path.expanduser(args.cases)
    ids = sorted(i for i in ideals if os.path.isdir(os.path.join(cases, i)))
    variant = json.load(open(args.variant)) if args.variant else {}
    name = "baseline" if args.baseline else variant.get("name", "variant")

    if args.baseline:
        replies = {i: json.load(open(os.path.join(cases, i, "reply.json"))) for i in ids}
    else:
        key = os.environ.get("AI_GATEWAY_API_KEY")
        if not key:
            sys.exit("Set AI_GATEWAY_API_KEY.")
        with futures.ThreadPoolExecutor(8) as pool:
            replies = dict(zip(ids, pool.map(lambda i: send(request_for(os.path.join(cases, i), variant), key), ids)))

    rows, failed = [], 0
    for i in ids:
        criteria = variant.get("questions", {}).get("automatable", {}).get("criteria") if not args.baseline else None
        steps = len(criteria or json.load(open(os.path.join(cases, i, "request.json")))["questions"]["automatable"]["criteria"])
        got = answers(replies[i], steps)
        if got is None:
            failed += 1
            continue
        rows.append({"id": i, "ideal": ideals[i], "got": got})
    result = {"variant": name, **score(rows), "failed": failed}
    print(json.dumps(result))
    if args.out:
        with open(os.path.expanduser(args.out), "w") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")


if __name__ == "__main__":
    main()
