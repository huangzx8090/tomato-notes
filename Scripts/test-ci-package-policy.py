#!/usr/bin/env python3
"""在临时 Git 仓库中验证 CI 打包策略，不读取或修改应用资料。"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


POLICY = Path(__file__).resolve().with_name("ci-package-needed.sh")


class PackagePolicyTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="tomato-ci-policy-")
        self.addCleanup(directory.cleanup)
        self.repo = Path(directory.name)
        self.git("init", "--quiet", "--initial-branch=main")
        self.base = self.commit({
            "README.md": "base\n",
            "apps/macos/Sources/App.swift": "// base\n",
            "apps/macos/Packaging/Info.plist": "base\n",
        })

    def git(self, *args):
        return subprocess.check_output([
            "git", "-c", "user.name=CI Policy Test",
            "-c", "user.email=ci-policy@example.invalid",
            "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
            *args,
        ], cwd=self.repo, text=True).strip()

    def commit(self, changes):
        for name, content in changes.items():
            path = self.repo / name
            if content is None:
                path.unlink()
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
        self.git("add", "-A")
        self.git("commit", "--quiet", "-m", "fixture")
        return self.git("rev-parse", "HEAD")

    def policy(self, event, base=None, head="HEAD", package="false"):
        env = os.environ.copy()
        env.update({
            "CI_EVENT_NAME": event,
            "CI_BASE_SHA": self.base if base is None else base,
            "CI_HEAD_SHA": head,
            "CI_PACKAGE": package,
        })
        return subprocess.run(["bash", str(POLICY)], cwd=self.repo, env=env,
                              text=True, capture_output=True, check=False)

    def assertPackage(self, expected, event="pull_request", **kwargs):
        result = self.policy(event, **kwargs)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(expected).lower())

    def test_source_and_docs_only_skip_packaging(self):
        self.commit({"apps/macos/Sources/App.swift": "// updated\n", "README.md": "docs\n"})
        for event in ("push", "pull_request"):
            with self.subTest(event=event):
                self.assertPackage(False, event)

    def test_packaging_inputs_trigger_packaging(self):
        previous = self.base
        for path in ("apps/macos/Packaging/Info.plist", "Scripts/build-app.sh",
                     "VERSION",
                     "apps/macos/Scripts/build-app.sh", "apps/windows/Scripts/package-windows.ps1",
                     "Scripts/ci-package-needed.sh", ".github/workflows/ci.yml",
                     ".github/workflows/release.yml", "apps/windows/TomatoNotes/App.xaml.cs",
                     "apps/windows/Packaging/TomatoNotes.iss", "apps/macos/Package.swift",
                     "apps/macos/Package.resolved"):
            with self.subTest(path=path):
                head = self.commit({path: "changed\n"})
                self.assertPackage(True, base=previous, head=head)
                previous = head

    def test_push_checks_all_commits_in_the_push(self):
        self.commit({"apps/macos/Packaging/Info.plist": "updated\n"})
        self.commit({"apps/macos/Sources/App.swift": "// updated\n"})
        self.assertPackage(True, "push")

    def test_pr_ignores_changes_only_on_target_branch(self):
        target = self.commit({"apps/macos/Packaging/Info.plist": "target change\n"})
        self.git("checkout", "--quiet", "-b", "feature", self.base)
        self.commit({"apps/macos/Sources/App.swift": "// feature change\n"})
        self.assertPackage(False, base=target)

    def test_pr_keeps_packaging_changes_after_target_branch_advances(self):
        target = self.commit({"README.md": "target change\n"})
        self.git("checkout", "--quiet", "-b", "feature", self.base)
        self.commit({"apps/macos/Packaging/Info.plist": "feature change\n"})
        self.assertPackage(True, base=target)

    def test_removing_packaging_input_triggers_packaging(self):
        self.commit({"apps/macos/Packaging/Info.plist": None})
        self.assertPackage(True)

    def test_moving_file_out_of_packaging_triggers_packaging(self):
        self.git("mv", "apps/macos/Packaging/Info.plist", "Info.plist")
        self.commit({})
        self.assertPackage(True)

    def test_missing_history_conservatively_triggers_packaging(self):
        for base in ("", "0" * 40, "a" * 40):
            with self.subTest(base=base):
                self.assertPackage(True, "push", base=base)
        self.assertPackage(True, head="a" * 40)

    def test_manual_runs_follow_explicit_selection(self):
        self.assertPackage(False, "workflow_dispatch")
        self.assertPackage(True, "workflow_dispatch", package="true")
        self.commit({"apps/macos/Packaging/Info.plist": "updated\n"})
        self.assertPackage(False, "workflow_dispatch")

    def test_invalid_manual_selection_fails(self):
        self.assertNotEqual(self.policy("workflow_dispatch", package="invalid").returncode, 0)

    def test_unknown_event_fails(self):
        self.assertNotEqual(self.policy("unknown").returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
