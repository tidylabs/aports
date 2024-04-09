#!/usr/bin/env python3

import argparse
import itertools
import os
import re
import subprocess

from pathlib import Path


class Package:
    def __init__(self, path):
        apkbuild_output = subprocess.check_output(
            f". /usr/share/abuild/functions.sh; . {path}; set",
            text=True, shell=True)

        apkbuild_vars = {}
        for m in re.finditer(r"(\w+)='((?:[^']|'\"'+\"')*)'", apkbuild_output):
            key = m.group(1)
            value = re.sub(r"'\"('+)\"'", r"\1", m.group(2))
            apkbuild_vars[key] = value

        def parse_str(key):
            return apkbuild_vars.get(key, "").strip()

        def parse_int(key):
            return int(apkbuild_vars.get(key, "0"))

        def parse_list(key):
            return re.findall(r"[^\s]+", apkbuild_vars.get(key, ""))

        def parse_deps(key):
            value = apkbuild_vars.get(key, "")
            return re.findall(r"([\w.-]+)(?:[=<>~]+[\w.-]+)?", value)

        def parse_subpkgs(key):
            value = apkbuild_vars.get(key, "")
            return re.findall(r"([\w.-]+)(?:\:\w+)*", value)

        self.pkgname = parse_str("pkgname")
        self.pkgver = parse_str("pkgver")
        self.pkgrel = parse_int("pkgrel")
        self.pkgdesc = parse_str("pkgdesc")

        self.arch = parse_list("arch")
        self.options = parse_list("options")
        self.provides = parse_deps("provides")
        self.subpackages = parse_subpkgs("subpackages")

        self.makedepends = parse_deps("makedepends")
        self.makedepends_build = parse_deps("makedepends_build")
        self.makedepends_host = parse_deps("makedepends_host")
        self.checkdepends = parse_deps("checkdepends")

        self.path = path

    def alldepends(self):
        return itertools.chain(
            self.makedepends,
            self.makedepends_build,
            self.makedepends_host,
            self.checkdepends
        )


def topological_sorted(nodes, edges):
    visited = {n: False for n in nodes}

    ordered = []
    visit = []
    for n in nodes:
        if visited[n]:
            continue
        visit.append((n, iter(edges(n))))
        while visit:
            n2, e2 = visit.pop()
            visited[n2] = True
            try:
                n3 = next(e2)
                visit.append((n2, e2))
                if not visited.get(n3, True):
                    visit.append((n3, iter(edges(n3))))
            except StopIteration:
                ordered.append(n2)
    return ordered


def build_order(packages):
    pkgs_by_alias = {}
    for pkg in packages:
        for subpkg_name in pkg.subpackages:
            pkgs_by_alias[subpkg_name] = pkg
        for provides_name in pkg.provides:
            pkgs_by_alias[provides_name] = pkg
        pkgs_by_alias[pkg.pkgname] = pkg

    def name(pkg):
        return pkg.pkgname

    def depends(pkg):
        deps = []
        for dep_name in pkg.alldepends():
            if dep := pkgs_by_alias.get(dep_name, None):
                deps.append(dep)
        return sorted(deps, key=name)

    return topological_sorted(sorted(packages, key=name), depends)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Build a local aports package repository",
    )
    parser.add_argument(
        "repo",
        nargs="*",
        type=Path,
        default=[Path(".")],
        help="Directory containing APKBUILD files (default: \".\")")
    args = parser.parse_args()

    apkbuild_files = set()
    for repo_dir in args.repo:
        if repo_dir.is_file() and repo_dir.name == "APKBUILD":
            apkbuild_files.add(repo_dir.resolve())
            continue
        for apkbuild_file in repo_dir.rglob("APKBUILD"):
            apkbuild_files.add(apkbuild_file.resolve())

    packages_by_name = {}
    for apkbuild_file in apkbuild_files:
        pkg = Package(apkbuild_file)
        packages_by_name[pkg.pkgname] = pkg

    packages_sorted = build_order(packages_by_name.values())
    for pkg in packages_sorted:
        os.putenv("APKBUILD", pkg.path)
        subprocess.run(["ccache", "-z"])
        subprocess.run(["abuild", "-c", "-r", "-F", "-k"])
        subprocess.run(["ccache", "-s", "-vv"])

