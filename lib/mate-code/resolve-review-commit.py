#!/usr/bin/env python3
"""Resolve an absent Git commit through configured remotes without checkout."""
import hashlib
import os
import re
import signal
import shutil
import shlex
import subprocess
import sys
import time
import urllib.parse


class ResolutionError(Exception):
    pass


class Resolver:
    def __init__(self, revision):
        self.revision = revision.lower()
        self.deadline = time.monotonic() + 120
        self.requests = 0
        self.failures = []
        self.cnb_retry = set()

    def git(self, *args, network=False, cnb_helper=False):
        timeout = 10
        if network:
            self.requests += 1
            remaining = self.deadline - time.monotonic()
            if remaining <= 0 or self.requests > 24:
                raise ResolutionError("远端查找达到时间或请求上限，请使用完整 hash 并确认远端访问权限。")
            timeout = min(30, remaining)
        env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
        command = ["git", "-c", "http.lowSpeedLimit=1000", "-c", "http.lowSpeedTime=15"]
        if cnb_helper:
            # An old system-keychain password can mask an active CNB CLI login.
            # Override helpers for this process only; never erase credentials or
            # change the user's Git configuration.
            helper = "!" + shlex.quote(shutil.which("cnb")) + " git-credential"
            command.extend(["-c", "credential.helper=", "-c", "credential.helper=" + helper])
        command.extend(args)
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env=env, text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
            return process.returncode, stdout, stderr
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            return 124, "", "timeout"

    def remote_git(self, remote, *args):
        result = self.git(*args, network=True, cnb_helper=remote in self.cnb_retry)
        if result[0] and remote not in self.cnb_retry and shutil.which("cnb"):
            _, url, _ = self.git("remote", "get-url", remote)
            parsed = urllib.parse.urlsplit(url.strip())
            if (parsed.scheme in ["http", "https"] and parsed.hostname == "cnb.cool"
                    and self.error_category(result[0], result[2]) == "仓库不存在或当前身份无访问权限"):
                self.cnb_retry.add(remote)
                print(f"{remote}：尝试当前 CNB 登录凭据（不修改系统钥匙串）…", file=sys.stderr)
                result = self.git(*args, network=True, cnb_helper=True)
        return result

    def local(self):
        code, output, _ = self.git("rev-parse", "--disambiguate=" + self.revision)
        if code:
            return None
        commits = []
        for candidate in output.splitlines():
            code, kind, _ = self.git("cat-file", "-t", candidate)
            if code == 0 and kind.strip() == "commit":
                commits.append(candidate)
        if len(commits) > 1:
            raise ResolutionError("这个短 hash 对应多个 commit，请输入更长或完整的 commit hash。")
        return commits[0] if commits else None

    @staticmethod
    def error_category(code, error):
        lower = error.lower()
        if any(value in lower for value in ["not found", "does not exist", "仓库不存在", "authentication", "permission denied", "access denied", "403", "401"]):
            return "仓库不存在或当前身份无访问权限"
        if code == 124 or "timeout" in lower or "timed out" in lower:
            return "连接超时"
        if any(value in lower for value in ["ssl", "tls", "could not resolve", "unable to access", "connection"]):
            return "网络或 TLS 连接失败"
        return "远端没有提供此对象，或拒绝了获取请求"

    def fetch(self, remote, *refspecs, deepen=False):
        args = ["fetch", "--quiet", "--no-tags", "--no-write-fetch-head"]
        if deepen:
            args.append("--unshallow")
        code, _, error = self.remote_git(remote, *args, remote, *refspecs)
        if code:
            self.failures.append((remote, self.error_category(code, error)))
        return code

    def resolve(self):
        found = self.local()
        if found:
            return found
        _, output, _ = self.git("remote")
        remotes = output.splitlines()
        if not remotes:
            raise ResolutionError("找不到这个 commit，且当前仓库没有配置 remote。")
        if "origin" in remotes:
            remotes.remove("origin")
            remotes.insert(0, "origin")
        _, output, _ = self.git("rev-parse", "--is-shallow-repository")
        shallow = output.strip() == "true"
        for remote in remotes:
            print(f"正在查找 {remote} 上的 commit（不切换分支）…", file=sys.stderr)
            if len(self.revision) in [40, 64]:
                self.fetch(remote, self.revision)
                found = self.local()
                if found:
                    return found
            code, output, error = self.remote_git(remote, "ls-remote", "--refs", remote)
            if code:
                category = self.error_category(code, error)
                self.failures.append((remote, category))
                print(f"{remote}：{category}。", file=sys.stderr)
                continue
            refs = []
            for line in output.splitlines():
                fields = line.split("\t", 1)
                if len(fields) == 2 and re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", fields[0]):
                    refs.append(fields)
            # Fetch matching tips first. A short hash cannot be sent directly to
            # upload-pack: expand it from advertised refs when possible.
            tips = [ref for sha, ref in refs if sha.startswith(self.revision)]
            namespace = "refs/mate-review/" + hashlib.sha256(remote.encode()).hexdigest()[:12]
            if tips:
                self.fetch(remote, *[f"+{ref}:{namespace}/{ref[5:]}" for ref in tips[:64]])
                found = self.local()
                if found:
                    return found
            # Include provider-specific PR refs, as well as branches and tags.
            # Dedicated cache refs never update local branches, tags or files.
            namespaces = sorted({ref.split("/", 2)[1] for _, ref in refs if ref.startswith("refs/") and ref.count("/") >= 2})
            if namespaces:
                print(f"{remote}：查找分支、标签及 PR 历史…", file=sys.stderr)
                self.fetch(remote, *[f"+refs/{name}/*:{namespace}/{name}/*" for name in namespaces], deepen=shallow)
                found = self.local()
                if found:
                    return found
                if shallow:
                    _, output, _ = self.git("rev-parse", "--is-shallow-repository")
                    shallow = output.strip() == "true"
        errors = list(dict.fromkeys(self.failures))
        detail = "；".join(f"{remote}：{category}" for remote, category in errors)
        if detail:
            detail += "。"
        raise ResolutionError(detail + "未找到该 commit。请确认 hash 属于此仓库；完整 hash 可获取未被分支或 PR 引用的对象，但仍需要远端权限。")


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r"[0-9a-fA-F]{7,64}", sys.argv[1]):
        raise ResolutionError("请输入有效的 commit hash（至少 7 位）。")
    print(Resolver(sys.argv[1]).resolve())


if __name__ == "__main__":
    try:
        main()
    except ResolutionError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except (OSError, subprocess.SubprocessError):
        print("无法运行 Git 查找 commit，请检查 Git 与网络环境。", file=sys.stderr)
        sys.exit(1)
