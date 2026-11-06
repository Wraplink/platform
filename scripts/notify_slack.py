#!/usr/bin/env python3
"""Send selected GitHub events to Slack using a secret incoming webhook."""
import json
import os
import sys
import urllib.error
import urllib.request


def short(value, limit=240):
    return str(value or "").replace("\\n", " ").replace("\\r", " ")[:limit]


def build_message(event, payload, repo, run_url):
    action = payload.get("action", "")
    if event == "issues":
        issue = payload.get("issue", {})
        if action not in ("opened", "reopened", "closed"):
            return None
        return f"🎫 *Issue {action}* · {repo}\\n<{issue.get('html_url', run_url)}|#{issue.get('number', '?')} {short(issue.get('title'))}>"
    if event == "pull_request_target":
        pr = payload.get("pull_request", {})
        if action == "closed" and pr.get("merged"):
            action = "merged"
        if action not in ("opened", "reopened", "closed", "merged", "ready_for_review"):
            return None
        return f"🔀 *Pull request {action}* · {repo}\\n<{pr.get('html_url', run_url)}|#{pr.get('number', '?')} {short(pr.get('title'))}>"
    if event == "workflow_run":
        workflow = payload.get("workflow_run", {})
        if workflow.get("conclusion") != "failure":
            return None
        return f"🚨 *CI/CD failed* · {repo}\\n<{workflow.get('html_url', run_url)}|{short(workflow.get('name'))}> · branch \`{short(workflow.get('head_branch'), 80)}\`"
    if event == "workflow_dispatch":
        message = payload.get("inputs", {}).get("message", "WrapLink Slack integration test")
        return f"🧪 *Integration test* · {repo}\\n{short(message)}"
    return None


def main():
    webhook = os.getenv("SLACK_WEBHOOK_URL")
    if not webhook:
        print("Slack webhook secret not configured; skipping notification.")
        return 0
    with open(os.environ["EVENT_PATH"], encoding="utf-8") as handle:
        payload = json.load(handle)
    message = build_message(os.environ["EVENT_NAME"], payload, os.environ["REPOSITORY"], os.environ["RUN_URL"])
    if not message:
        return 0
    request = urllib.request.Request(
        webhook,
        data=json.dumps({"text": message}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            if response.status != 200:
                print(f"Slack returned HTTP {response.status}", file=sys.stderr)
                return 1
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"Slack delivery failed: {type(exc).__name__}", file=sys.stderr)
        return 1
    print("Slack notification delivered.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
