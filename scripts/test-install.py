#!/usr/bin/env python3
"""Offline regression checks: missing Neovim config, backups and repeat installs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def test_nvm_loads_with_strict_shell_and_selects_existing_default(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            nvm_dir = home / ".nvm"
            nvm_dir.mkdir()
            (nvm_dir / "nvm.sh").write_text('''
test -n "$NVM_DIR"
# Model nvm's use of unset variables; the installer must disable nounset here.
test -z "$DOTFILES_NVM_UNSET_TEST"
nvm() {
  case "$1" in
    version) echo v99.0.0 ;;
    use) touch "$NVM_DIR/selected" ;;
    *) return 1 ;;
  esac
}
''')
            env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / ".local/state"))
            env.pop("NVM_DIR", None)
            env.pop("DOTFILES_NVM_UNSET_TEST", None)
            subprocess.run([str(REPO / "install.sh"), "--skip-deps"],
                           env=env, check=True, capture_output=True, text=True)
            self.assertTrue((nvm_dir / "selected").exists())

    def test_neovim_directory_and_commands_are_installed(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self.install(home)
            self.assertTrue((home / ".config/nvim").is_symlink())
            self.assertEqual((home / ".config/nvim").resolve(), (REPO / "config/nvim").resolve())
            for command in ("mcode", "mreview"):
                self.assertEqual((home / ".local/bin" / command).resolve(), REPO / "bin" / command)
            self.assertTrue((home / ".config/nvim/lazy-lock.json").is_file())

    def test_existing_neovim_directory_is_backed_up_and_rerun_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            original = home / ".config/nvim"
            original.mkdir(parents=True)
            (original / "init.lua").write_text("-- original config\n")
            (home / ".zshrc").write_text("# original zsh\n")
            self.install(home)
            backups = home / ".local/state/echin-dotfiles/backups"
            before = list(backups.iterdir())
            self.assertEqual(len(before), 1)
            self.assertEqual((before[0] / "nvim/init.lua").read_text(), "-- original config\n")
            self.assertEqual((before[0] / ".zshrc").read_text(), "# original zsh\n")
            self.install(home)
            self.assertEqual(list(backups.iterdir()), before)
            self.assertEqual(original.resolve(), REPO / "config/nvim")

    def install(self, home):
        env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / ".local/state"))
        subprocess.run([str(REPO / "install.sh"), "--skip-deps", "--skip-node"],
                       env=env, check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
