"""Fail-closed reuse of recent simulator evidence for Info.plist version repairs only."""
import datetime
import json
import os
from pathlib import Path
import re
import subprocess


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def normalized_project(text):
    for field, value in [
        ("CFBundleShortVersionString", r'(?:\d+\.\d+\.\d+|\$\(MARKETING_VERSION\))'),
        ("CFBundleVersion", r'(?:\d+|\$\(CURRENT_PROJECT_VERSION\))'),
    ]:
        text, count = re.subn(r'(?m)^(\s*' + field + r':) "' + value + r'"\s*$', r'\1 VERSION', text)
        if count != 1:
            raise ValueError("Expected exactly one well-formed bundle version field")
    return text


def validate_diff(changed, before, after):
    allowed = {"project.yml", ".github/workflows/ios-release.yml",
               "Scripts/verify_test_reuse.py", "Scripts/test_verify_test_reuse.py"}
    if set(changed) - allowed:
        raise ValueError("App, tests, assets or dependencies changed; run the full simulator suite")
    if normalized_project(before) != normalized_project(after):
        raise ValueError("Non-version project settings changed; run the full simulator suite")


def main():
    run_id = os.environ.get("REUSE_SIMULATOR_RUN", "")
    reused = False
    if run_id:
        if not re.fullmatch(r"[0-9]+", run_id):
            raise ValueError("Invalid run id")
        repo = os.environ["GITHUB_REPOSITORY"]
        run = json.loads(command("gh", "api", f"repos/{repo}/actions/runs/{run_id}"))
        if run["head_repository"]["full_name"] != repo or run["path"] != ".github/workflows/ios-release.yml" or run["status"] != "completed":
            raise ValueError("Evidence must come from this repository's completed release workflow")
        created = datetime.datetime.fromisoformat(run["created_at"].replace("Z", "+00:00"))
        age = datetime.datetime.now(datetime.timezone.utc) - created
        if not datetime.timedelta(0) <= age <= datetime.timedelta(hours=24):
            raise ValueError("Simulator evidence must be less than 24 hours old")
        jobs = json.loads(command("gh", "api", f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100"))["jobs"]
        if not any(j["name"] == "simulator-test" and j["conclusion"] == "success" for j in jobs):
            raise ValueError("The referenced simulator job did not pass")
        sha = run["head_sha"]
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            raise ValueError("Invalid evidence commit")
        subprocess.run(["git", "merge-base", "--is-ancestor", sha, "HEAD"], check=True)
        before = command("git", "show", f"{sha}:project.yml")
        after = Path("project.yml").read_text().strip()
        changes = command("git", "diff", "--name-only", sha, "HEAD").splitlines()
        validate_diff(changes, before, after)
        old_workflow = command("git", "show", f"{sha}:.github/workflows/ios-release.yml")
        current_workflow = Path(".github/workflows/ios-release.yml").read_text()
        toolchain = r"DEVELOPER_DIR: (.+)"
        if re.search(toolchain, old_workflow).group(1) != re.search(toolchain, current_workflow).group(1):
            raise ValueError("Xcode toolchain changed; rerun simulator tests")
        print(f"Verified passing simulator run {run_id} at {sha}; app source/tests unchanged, bundle-version metadata repair only.")
        reused = True
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"reused={str(reused).lower()}\n")


if __name__ == "__main__":
    main()
