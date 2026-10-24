"""Write one eval's fixture files and plugin config; optionally seed its server.

usage: python3 tests/evals/setup.py <iteration> <skill> <eval_id> <server_id|none>
                                    [--seed-project] [--endpoint URL]

- Fixtures (the eval's `files`, minus `_simulated/*`) go to
  cyoda-evals-workspace/<iteration>/<skill>/eval-<id>/with_skill/outputs/project/.
- A `*cyoda-plugin-config*` fixture becomes outputs/plugin-config.json, with the
  active profile pointed at the eval server (20000+id*100+80) or --endpoint.
- --seed-project registers each src/data/<e>-v1-sample.json (sample, lock, and
  src/workflows/<e>-v1-workflow.json if present) on that server.
"""
import glob
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def main(argv):
    if len(argv) < 5:
        sys.exit(__doc__)
    it, skill, eid, sid = argv[1], argv[2], int(argv[3]), argv[4]
    seed = "--seed-project" in argv
    if "--endpoint" in argv:
        ep = argv[argv.index("--endpoint") + 1]
    elif sid != "none":
        ep = f"http://localhost:{20000 + int(sid) * 100 + 80}"
    else:
        ep = None

    evals = json.load(open(f"{REPO}/cyoda/skills/{skill}/evaluations/evals.json"))["evals"]
    e = next(x for x in evals if x["id"] == eid)
    out = f"{REPO}/cyoda-evals-workspace/{it}/{skill}/eval-{eid}/with_skill/outputs"
    proj = f"{out}/project"
    os.makedirs(proj, exist_ok=True)

    for k, v in e.get("files", {}).items():
        if k.startswith("_simulated"):
            continue
        v = v if isinstance(v, str) else json.dumps(v, indent=1)
        if "cyoda-plugin-config" in k:
            c = json.loads(v)
            if ep:
                for name, p in c["profiles"].items():
                    if name == c["active"]:
                        p["endpoint"] = ep
                    else:
                        p["endpoint"] = p["endpoint"].replace("localhost:8080", ep.split("//")[1])
            with open(f"{out}/plugin-config.json", "w") as f:
                f.write(json.dumps(c, indent=1))
            continue
        fp = f"{proj}/{k}"
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        with open(fp, "w") as f:
            f.write(v)

    if seed and sid != "none":
        seed_server(ep, proj, skill, eid)
    print(f"setup {skill} {eid} -> {ep or 'no profile'} ({out})")


def seed_server(ep, proj, skill, eid):
    sv = subprocess.run(
        ["bash", "-c", "cyoda help workflows schema-version versions | jq -r .current"],
        capture_output=True, text=True).stdout.strip()

    def call(method, path, body=None):
        req = urllib.request.Request(
            f"{ep}/api{path}", method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Content-Type": "application/json"})
        try:
            return urllib.request.urlopen(req).status
        except urllib.error.HTTPError as x:
            return x.code

    for s in sorted(glob.glob(f"{proj}/src/data/*-v1-sample.json")):
        ent = os.path.basename(s).split("-v1-")[0]
        wf = f"{proj}/src/workflows/{ent}-v1-workflow.json"
        st = [call("POST", f"/model/import/JSON/SAMPLE_DATA/{ent}/1", json.load(open(s))),
              call("PUT", f"/model/{ent}/1/lock")]
        if os.path.exists(wf):
            doc = json.loads(open(wf).read().replace("${SCHEMA_VERSION}", sv))
            st.append(call("POST", f"/model/{ent}/1/workflow/import", {"workflows": doc["workflows"]}))
        print(skill, eid, ent, st)


if __name__ == "__main__":
    main(sys.argv)
