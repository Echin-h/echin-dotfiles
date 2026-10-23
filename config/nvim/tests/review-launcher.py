"""Run: python3 ~/.config/nvim/tests/review-launcher.py"""
import json
import os
from pathlib import Path
import subprocess
import tempfile


def run():
    with tempfile.TemporaryDirectory(prefix="review-launcher-test-") as directory:
        root = Path(directory)
        repo = root / "repo"
        repo.mkdir()

        def git(*args):
            return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()

        git("init", "-qb", "main")
        git("config", "user.name", "Review Test")
        git("config", "user.email", "review-test@example.invalid")
        (repo / "test.txt").write_text("before\n")
        git("add", ".")
        git("-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "before")
        base = git("rev-parse", "HEAD")
        git("checkout", "-qb", "feature/test")
        (repo / "test.txt").write_text("after\n")
        git("add", ".")
        git("-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "after")
        head = git("rev-parse", "HEAD")
        (repo / "test.txt").write_text("dirty\n")
        # Exercise the installed launcher, intercepting only the final editor exec.
        capture = root / "capture.py"
        capture.write_text("import os,json\nprint(json.dumps({k:v for k,v in os.environ.items() if k.startswith('MATE_REVIEW_')}))\n")
        launcher = root / "mreview"
        source = Path(os.environ.get("MREVIEW_TEST_LAUNCHER", str(Path.home() / ".local/bin/mreview"))).read_text()
        editor = 'exec "$review_editor"'
        assert source.count(editor) == 3, "launcher editor entry points changed"
        import shlex
        launcher.write_text(source.replace(editor, "exec /usr/bin/python3 " + shlex.quote(str(capture))))
        env = {key: value for key, value in os.environ.items() if not key.startswith("MATE_REVIEW_")}
        env["MATE_REVIEW_BASE"] = "main"

        def launch(*args):
            result = subprocess.run(["zsh", str(launcher), *args], cwd=repo, env=env, capture_output=True, text=True, check=True)
            return json.loads(result.stdout)

        for args, mode, revision in [
            ((), "diff", "main...HEAD"),
            (("feature/test",), "diff", "main...feature/test"),
            (("main", "feature/test"), "diff", "main..feature/test"),
            (("main..feature/test",), "diff", "main..feature/test"),
            (("main...feature/test",), "diff", "main...feature/test"),
            ((head,), "commit", head + "^!"),
            (("--commit", base), "commit", base + "^!"),
            (("--history",), "history", "HEAD"),
            (("--history", "main..feature/test"), "history", "main..feature/test"),
        ]:
            result = launch(*args)
            assert result["MATE_REVIEW_MODE"] == mode, (args, result)
            assert result["MATE_REVIEW_RANGE"] == revision, (args, result)
        assert launch("feature/test")["MATE_REVIEW_HISTORY_RANGE"] == base + "..feature/test"
        assert git("branch", "--show-current") == "feature/test"
        assert (repo / "test.txt").read_text() == "dirty\n"
        assert git("status", "--porcelain") == "M test.txt"
        print("PASS: branch opens overall diff; explicit history, commits, ranges, dirty checkout preserved")


if __name__ == "__main__":
    run()
