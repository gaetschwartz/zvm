import json
import re
import subprocess
import sys
from typing import Optional

# class Zvm < Formula
#   desc "Simple yet powerful version manager for Zig"
#   homepage "https://github.com/gaetschwartz/zvm"
#   url "https://github.com/gaetschwartz/zvm/archive/0.1.1.tar.gz"
#   sha256 "1333c7488bea9df19e25eb55c479a2084e6df0da847922daef69a15d331b0b59"
#   license "MIT"

#   on_macos do
#     if Hardware::CPU.arm?
#       resource "zig" do
#         url "https://ziglang.org/builds/zig-macos-aarch64-0.11.0-dev.1606+3c2a43fdc.tar.xz"
#         sha256 "203bd59d6073346c8a23ab3f5507c8667682a857a7bbc39423df0f8388840fd0"
#       end
#     else
#       resource "zig" do
#         url "https://ziglang.org/builds/zig-macos-x86_64-0.11.0-dev.1606+3c2a43fdc.tar.xz"
#         sha256 "6e66506952ba89f3ee83753739db223e326a264a47d28d382a729720aa0152f9"
#       end
#     end
#   end
#   on_linux do
#     if Hardware::CPU.arm?
#       resource "zig" do
#         url "https://ziglang.org/builds/zig-linux-aarch64-0.11.0-dev.1606+3c2a43fdc.tar.xz"
#         sha256 "2d116916f95c684cd663801425341e55085810e50126740c94ce5b669c5dc712"
#       end
#     else
#       resource "zig" do
#         url "https://ziglang.org/builds/zig-linux-x86-0.11.0-dev.1606+3c2a43fdc.tar.xz"
#         sha256 "3ed621c4443a46d6058bdc08cb0f06f7fba6063cad6b6b93ac2cf6035220262b"
#       end
#     end
#   end

#   resource "known-folders" do
#     url "https://github.com/ziglibs/known-folders/archive/53fe3b676f32e59d46f4fd201d7ab200e5f6cb98.tar.gz"
#     sha256 "3c9d1e293df9e3e48b96114859267c2bf5d8cc924e7e5f7a9628d0c77bb43709"
#   end

#   def install
#     resource("zig").unpack "ziglang-org/zig"
#     resource("known-folders").unpack "known-folders"
#     system "ziglang-org/zig/zig", "build", "-Doptimize=ReleaseSafe"
#     bin.install "zig-out/bin/zvm"
#   end

#   test do
#     system "#{bin}/zvm", "--version", "--verbose"
#   end
# end


def hash_for_url(url: str) -> str:
    # curl -L -o archive.tar.gz <url>
    subprocess.check_output(["curl", "-L", "-o", "archive.tar.gz", url])
    # sha256sum archive.tar.gz
    hash = (
        subprocess.check_output(["sha256sum", "archive.tar.gz"], encoding="utf-8")
        .strip()
        .split(" ")[0]
    )
    # delete archive.tar.gz
    subprocess.check_output(["rm", "archive.tar.gz"])
    return hash


def main(forumla: str, overwrite_path: Optional[str] = None):
    print("Updating formula for {}".format(forumla))
    # brew livecheck --newer-only --json --formula <formula>
    cmd = ["brew", "livecheck", "--json", "--formula", forumla]
    output = subprocess.check_output(cmd).strip()
    print(output)
    # parse json
    data = json.loads(output)[0]
    latest = data["version"]["latest"]
    current = data["version"]["current"]
    if current == latest:
        print("No update needed.")
        return
    print("Updating formula to {}".format(latest))
    # brew formula
    cmd = ["brew", "formula", forumla]
    formula_path = subprocess.check_output(cmd, encoding="utf-8").strip()
    print("Formula path: {}".format(formula_path))
    # read formula
    with open(formula_path, "r") as f:
        content = f.read()
        # replace the regex to find : 'url "https://github.com/gaetschwartz/zvm/archive/<version>.tar.gz"'
        url_fmt = "https:/github.com/gaetschwartz/zvm/archive/v{}.tar.gz"
        old_url = url_fmt.format(current)
        new_url = url_fmt.format(latest)
        old_hash = hash_for_url(old_url)
        new_hash = hash_for_url(new_url)
        newContent = re.sub('url "{}"'.format(old_url), 'url "{}"'.format(new_url), content)
        newContent = re.sub(
            'sha256 "{}"'.format(old_hash), 'sha256 "{}"'.format(new_hash), newContent
        )
        if newContent == content and data["version"]["current"] != latest:
            print(newContent)
            print("didnt update ?")
            sys.exit(1)
        content = newContent
        # get all submodules
        # git submodule
        #         output: str = subprocess.check_output(
        #             ["git", "submodule"], encoding="utf-8", cwd="zvm-repo/"
        #         ).strip()
        #         known_folders_hash = output.splitlines()[0].split(" ")[0]
        #         new_known_folders_url = (
        #             "https://github.com/ziglibs/known-folders/archive/" + known_folders_hash + ".tar.gz"
        #         )

        #         known_folders_shasum = hash_for_url(new_known_folders_url)

        #         # replace the regex to find : 'url "
        #         content = re.sub(
        #             r"""
        #   resource "known-folders" do
        #     url "https:\/\/github\.com\/ziglibs\/known-folders\/archive\/[a-f0-9]+\.tar\.gz\"
        #     sha256 \"[a-f0-9]+\"
        #   end
        # """,
        #             r"""
        #   resource "known-folders" do
        #     url "https://github.com/ziglibs/known-folders/archive/{}.tar.gz"
        #     sha256 "{}"
        #   end
        # """.format(
        #                 known_folders_hash, known_folders_shasum
        #             ),
        #             content,
        #         )

        print("Updated version")
        print(content)
        # write formula
    overwrite_path = overwrite_path or formula_path
    print("Overwriting {}...".format(overwrite_path))
    with open(overwrite_path, "w") as f:
        f.write(content)


if __name__ == "__main__":
    formula = sys.argv[1]
    path = sys.argv[2] if len(sys.argv) > 2 else None
    main(formula, path)
