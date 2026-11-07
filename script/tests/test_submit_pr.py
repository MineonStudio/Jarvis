import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "submit_pr", Path(__file__).resolve().parents[1] / "submit_pr.py")
workflow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workflow)


class CleanupTests(unittest.TestCase):
    def test_unmerged_pr_never_touches_git(self):
        with patch.object(workflow, "read_pr", return_value={"merged": False}), \
                patch.object(workflow, "command") as command:
            with self.assertRaises(workflow.WorkflowError):
                workflow.cleanup_local("owner/repo", 1, "codex/task", "abc")
            command.assert_not_called()

    def simulate(self, *, dirty=False, changed_tip=False, diverged=False):
        calls = []

        def command(*args, **kwargs):
            calls.append(args)
            if args == ("git", "status", "--porcelain"):
                return " M user-file" if dirty else ""
            if args == ("git", "branch", "--show-current"):
                return "codex/task"
            if args == ("git", "rev-parse", "HEAD"):
                return "new-commit" if changed_tip else "abc"
            if args == ("git", "branch", "--list", "main"):
                return "main"
            if diverged and args == ("git", "merge-base", "--is-ancestor", "main", "origin/main"):
                raise workflow.WorkflowError("not ancestor")
            return ""

        return calls, command

    def test_dirty_worktree_is_preserved(self):
        calls, command = self.simulate(dirty=True)
        with patch.object(workflow, "read_pr", return_value={"merged": True}), \
                patch.object(workflow, "command", side_effect=command):
            with self.assertRaises(workflow.WorkflowError):
                workflow.cleanup_local("owner/repo", 1, "codex/task", "abc")
        self.assertEqual(calls, [("git", "status", "--porcelain")])

    def test_new_local_commit_is_not_deleted(self):
        calls, command = self.simulate(changed_tip=True)
        with patch.object(workflow, "read_pr", return_value={"merged": True}), \
                patch.object(workflow, "command", side_effect=command):
            with self.assertRaises(workflow.WorkflowError):
                workflow.cleanup_local("owner/repo", 1, "codex/task", "abc")
        self.assertFalse(any(c[:2] == ("git", "fetch") for c in calls))

    def test_main_with_unpushed_commits_is_not_overwritten(self):
        calls, command = self.simulate(diverged=True)
        with patch.object(workflow, "read_pr", return_value={"merged": True}), \
                patch.object(workflow, "command", side_effect=command):
            with self.assertRaisesRegex(workflow.WorkflowError, "独有提交"):
                workflow.cleanup_local("owner/repo", 1, "codex/task", "abc")
        self.assertFalse(any(c[:2] == ("git", "switch") for c in calls))
        self.assertNotIn(("git", "branch", "-D", "codex/task"), calls)

    def test_squash_cleanup_verifies_pr_ancestry_and_fast_forwards_first(self):
        calls, command = self.simulate()
        with patch.object(workflow, "read_pr", return_value={"merged": True}), \
                patch.object(workflow, "command", side_effect=command):
            workflow.cleanup_local("owner/repo", 1, "codex/task", "abc")
        self.assertIn(("git", "merge-base", "--is-ancestor", "abc", "FETCH_HEAD"), calls)
        self.assertLess(calls.index(("git", "merge", "--ff-only", "origin/main")),
                        calls.index(("git", "branch", "-D", "codex/task")))


class MergeTests(unittest.TestCase):
    def test_main_cannot_be_submitted(self):
        with patch.object(workflow, "command", return_value="main") as command:
            with self.assertRaisesRegex(workflow.WorkflowError, "功能分支"):
                workflow.submit(None)
        command.assert_called_once_with("git", "branch", "--show-current")

    def test_head_must_match_without_admin_bypass(self):
        with patch.object(workflow, "command") as command:
            workflow.queue_merge("owner/repo", 2, "abc")
        args = command.call_args.args
        self.assertIn("--match-head-commit", args)
        self.assertIn("--auto", args)
        self.assertIn("--squash", args)
        self.assertNotIn("--admin", args)

    def test_failed_check_stops_instead_of_reporting_merged(self):
        pr = {"merged": False, "state": "open", "draft": False,
              "head": {"sha": "abc"}, "mergeable_state": "blocked"}
        with patch.object(workflow, "read_pr", return_value=pr), \
                patch.object(workflow, "gh_json", return_value=[{"name": "quality", "bucket": "fail"}]), \
                patch.object(workflow.time, "sleep") as sleep:
            with self.assertRaisesRegex(workflow.WorkflowError, "quality"):
                workflow.wait_for_merge("owner/repo", 1, 5, 1)
            sleep.assert_not_called()

    def test_behind_branch_requests_update_for_the_exact_head(self):
        pending = {"merged": False, "state": "open", "draft": False,
                   "head": {"sha": "abc"}, "mergeable_state": "behind"}
        merged = {"merged": True}
        with patch.object(workflow, "read_pr", side_effect=[pending, merged]), \
                patch.object(workflow, "command") as command, \
                patch.object(workflow.time, "sleep"):
            self.assertEqual(workflow.wait_for_merge("owner/repo", 1, 5, 1), merged)
        self.assertIn("expected_head_sha=abc", command.call_args.args)

    def test_pending_branch_update_does_not_fail_on_old_checks(self):
        pending = {"merged": False, "state": "open", "draft": False,
                   "head": {"sha": "abc"}, "mergeable_state": "behind"}
        with patch.object(workflow, "read_pr", side_effect=[pending, pending, {"merged": True}]), \
                patch.object(workflow, "command") as command, \
                patch.object(workflow, "gh_json") as checks, \
                patch.object(workflow.time, "sleep"):
            workflow.wait_for_merge("owner/repo", 1, 5, 1)
        command.assert_called_once()
        checks.assert_not_called()


if __name__ == "__main__":
    unittest.main()
