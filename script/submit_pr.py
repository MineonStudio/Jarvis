#!/usr/bin/env python3
"""Submit the current task branch, queue auto-merge, and safely sync locally."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time


class WorkflowError(RuntimeError):
    pass


def command(*args, check=True):
    result = subprocess.run(args, text=True, capture_output=True)
    if check and result.returncode:
        raise WorkflowError(result.stderr.strip() or result.stdout.strip() or str(args))
    return result.stdout.strip()


def gh_json(*args, check=True):
    return json.loads(command("gh", *args, check=check) or "null")


def require_clean():
    if command("git", "status", "--porcelain"):
        raise WorkflowError("工作区有未提交改动，已停止；请先检查并提交本次任务的文件。")


def read_pr(repo, number):
    return gh_json("api", f"repos/{repo}/pulls/{number}")


def queue_merge(repo, number, head):
    command("gh", "pr", "merge", str(number), "--repo", repo,
            "--auto", "--squash", "--match-head-commit", head)


def wait_for_merge(repo, number, timeout, interval):
    deadline = time.monotonic() + timeout
    updated_heads = set()
    last_status = None
    while time.monotonic() < deadline:
        pr = read_pr(repo, number)
        if pr["merged"]:
            return pr
        if pr["state"] != "open":
            raise WorkflowError("PR 已关闭但没有合并，已停止。")
        if pr["draft"]:
            raise WorkflowError("PR 已转回草稿，已停止自动处理。")
        head = pr["head"]["sha"]
        status = pr.get("mergeable_state", "unknown")
        if status != last_status:
            print(f"PR #{number}: {status}", flush=True)
            last_status = status
        if status == "dirty":
            raise WorkflowError("PR 存在合并冲突，请解决冲突并验证后重试。")
        if status == "behind" and head not in updated_heads:
            command("gh", "api", "--method", "PUT",
                    f"repos/{repo}/pulls/{number}/update-branch",
                    "-f", f"expected_head_sha={head}")
            updated_heads.add(head)
            print("已请求同步远程 main；更新会重新触发 CI。", flush=True)
        elif status == "behind" and head in updated_heads:
            # The update endpoint is asynchronous; don't judge checks for the old head.
            pass
        else:
            checks = gh_json("pr", "checks", str(number), "--repo", repo,
                             "--required", "--json", "name,bucket", check=False) or []
            failed = [c["name"] for c in checks if c["bucket"] in ("fail", "cancel")]
            if failed:
                raise WorkflowError("必需检查失败或取消：" + ", ".join(failed)
                                    + "。保留 PR 和分支，修复后再次运行。")
        time.sleep(interval)
    raise WorkflowError("等待合并超时；已保留 PR、自动合并设置及本地分支。")


def cleanup_local(repo, number, branch, pushed_head):
    # Squash changes commit IDs: verify the PR's actual head contains our push.
    pr = read_pr(repo, number)
    if not pr["merged"]:
        raise WorkflowError("PR 未合并，禁止删除本地分支。")
    require_clean()
    if command("git", "branch", "--show-current") != branch:
        raise WorkflowError("当前分支已改变，跳过本地清理。")
    if command("git", "rev-parse", "HEAD") != pushed_head:
        raise WorkflowError("本地有新的提交，已保留功能分支。")
    command("git", "fetch", "origin", f"refs/pull/{number}/head")
    command("git", "merge-base", "--is-ancestor", pushed_head, "FETCH_HEAD")
    command("git", "fetch", "origin", "--prune")
    if command("git", "branch", "--list", "main"):
        try:
            command("git", "merge-base", "--is-ancestor", "main", "origin/main")
        except WorkflowError as error:
            raise WorkflowError("远程已合并；本地 main 有独有提交，已保留所有本地分支。"
                                "请先处理本地同步，不能 reset 或覆盖。") from error
        command("git", "switch", "main")
    else:
        command("git", "switch", "--track", "-c", "main", "origin/main")
    command("git", "merge", "--ff-only", "origin/main")
    # Only reached after merged-state, ancestry, clean-tree and tip checks.
    command("git", "branch", "-D", branch)
    print("本地 main 已同步，已清理本次功能分支。", flush=True)


def submit(args):
    branch = command("git", "branch", "--show-current")
    if not branch.startswith("codex/"):
        raise WorkflowError("只允许从 codex/ 功能分支提交，不能直接提交 main。")
    body_file = Path(args.body_file).resolve()
    if not body_file.is_file():
        raise WorkflowError("PR 描述文件不存在。")
    require_clean()
    remote = command("git", "remote", "get-url", "origin")
    repo_info = gh_json("repo", "view", remote, "--json", "nameWithOwner,defaultBranchRef")
    repo = repo_info["nameWithOwner"]
    if repo_info["defaultBranchRef"]["name"] != "main":
        raise WorkflowError("仓库默认分支不是 main，已停止。")
    settings = gh_json("api", f"repos/{repo}")
    if not settings.get("allow_auto_merge") or not settings.get("allow_squash_merge"):
        raise WorkflowError("仓库需先开启 Auto-merge 和 Squash 合并。")
    command("git", "fetch", "origin", "--prune")
    try:
        command("git", "merge-base", "--is-ancestor", "origin/main", "HEAD")
    except WorkflowError as error:
        raise WorkflowError("功能分支未包含最新 origin/main；请先同步并验证后重试。") from error
    pushed_head = command("git", "rev-parse", "HEAD")
    command("git", "push", "-u", "origin", branch)
    prs = gh_json("pr", "list", "--repo", repo, "--head", branch, "--base", "main",
                  "--state", "open", "--json", "number")
    if len(prs) > 1:
        raise WorkflowError("找到多个同名分支的 PR，已停止。")
    if not prs:
        command("gh", "pr", "create", "--repo", repo, "--base", "main", "--head", branch,
                "--title", args.title, "--body-file", str(body_file))
        prs = gh_json("pr", "list", "--repo", repo, "--head", branch, "--base", "main",
                      "--state", "open", "--json", "number")
    if len(prs) != 1:
        raise WorkflowError("无法唯一确定本次 PR，已停止。")
    number = prs[0]["number"]
    pr = read_pr(repo, number)
    if pr["head"]["repo"]["full_name"] != repo or pr["head"]["sha"] != pushed_head:
        raise WorkflowError("PR 来源或提交不匹配，未启用自动合并。")
    if pr["draft"]:
        command("gh", "pr", "ready", str(number), "--repo", repo)
    print(pr["html_url"], flush=True)
    queue_merge(repo, number, pushed_head)
    if args.no_wait:
        print("已启用自动合并；GitHub 会在必需检查满足后合并。", flush=True)
        return
    wait_for_merge(repo, number, args.timeout, args.interval)
    print("GitHub 已完成 Squash 合并。", flush=True)
    if not args.remote_only:
        cleanup_local(repo, number, branch, pushed_head)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", required=True)
    parser.add_argument("--body-file", required=True)
    parser.add_argument("--remote-only", action="store_true", help="合并后保留本地分支状态")
    parser.add_argument("--no-wait", action="store_true", help="启用自动合并后退出，不清理本地")
    parser.add_argument("--timeout", type=int, default=3600)
    parser.add_argument("--interval", type=int, default=20)
    args = parser.parse_args()
    if args.timeout < 1 or not 1 <= args.interval <= 60:
        parser.error("timeout 必须为正，interval 必须在 1 到 60 秒之间")
    try:
        submit(args)
    except (WorkflowError, json.JSONDecodeError) as error:
        print(f"自动提交停止：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
