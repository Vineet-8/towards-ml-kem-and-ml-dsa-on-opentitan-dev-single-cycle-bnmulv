# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def python_repos():
    http_archive(
        name = "rules_python",
    patch_cmds = ["""python3 -c "import os; p='python/pip_install/extract_wheels/lib/wheel.py'; c=open(p).read(); c=c.replace('return str(self.metadata.name)', 'return str(self.metadata.name) if self.metadata.name else os.path.basename(self.path).split(chr(45))[0]'); c=c.replace('metadata.name.replace', '(metadata.name or os.path.basename(self.path).split(chr(45))[0]).replace'); c=c.replace('metadata.version)', '(metadata.version or os.path.basename(self.path).split(chr(45))[1]))'); open(p, 'w').write(c)" """],
        sha256 = "9e9a58cff49f80afd1c9fcc7137b719531f7a7427cce4fda1d30ca27b4a46a8a",
        strip_prefix = "rules_python-07c3f8547abbd5b97839a48af226a0fbcfaa5e7c",
        url = "https://github.com/lowRISC/rules_python/archive/07c3f8547abbd5b97839a48af226a0fbcfaa5e7c.tar.gz",
    )
