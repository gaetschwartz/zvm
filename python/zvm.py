import argparse
import hashlib

# download the json file from https://ziglang.org/download/index.json
# and parse it into a python dict
import json
import os
import shutil
import sys
import tarfile
import time
import zipfile
from typing import Any, Dict, List, Literal, Optional

import colored as c
import requests
import tqdm


def bytes2human(n):
    # >>> bytes2human(10000)
    # '9.8K'
    # >>> bytes2human(100001221)
    # '95.4M'
    symbols = ("K", "M", "G", "T", "P")
    div = 1000
    for s in symbols:
        n /= div
        if n < div:
            return "%.1f%s" % (n, s)
    return "%.1f%s" % (n, symbols[-1])


def get_zig_mainfest() -> Dict[str, Any]:
    r = requests.get("https://ziglang.org/download/index.json")
    if r.status_code != 200:
        print(
            c.stylize("Failed to download zig manifest with status code", c.fg("red")),
            r.status_code,
        )
        sys.exit(1)
    data = json.loads(r.text)
    for key, value in data.items():
        if "version" not in value:
            value["version"] = key
    return data


# Here we parse the arguments provided using argparse
# here are the available commands:
#   * install <version> -      installs the specified version
#   * update <version> -       updates the specified version if the version is a channel (master, stable)
#   * uninstall <version> -    uninstalls the specified version
#   * list -                   lists all installed versions
#   * use <version> -          sets the current version to the specified version by symlinking the ~/.zvm/versions/<version>/zig folder to ~/.zvm/versions/current
#   * spawn <version> <args..> runs the specified version of zig with the provided arguments
#   * help -                   prints this help message


def get_platform() -> Literal["linux", "macos", "windows", "freebsd"]:
    """
    Returns the platform name.
    """
    if sys.platform.startswith("linux"):
        return "linux"
    elif sys.platform.startswith("darwin"):
        return "macos"
    elif sys.platform.startswith("win"):
        return "windows"
    elif sys.platform.startswith("freebsd"):
        return "freebsd"
    else:
        print(c.stylize(f"Unsupported platform {sys.platform}", c.fg("red")))
        sys.exit(1)


def get_arch() -> str:
    """
    Returns the architecture name.
    """
    import platform

    translations = {
        "arm64": "aarch64",
        "AMD64": "x86_64",
    }

    uname = platform.uname()
    arch = uname.machine
    if arch in translations:
        return translations[arch]
    return arch


def get_machine_name() -> str:
    """
    Returns the machine name.
    """
    return f"{get_arch()}-{get_platform()}"


## this function takes a version and installs it
# the file is downloaded to ~/.zvm/cache/web/<version>.tar.xz
# it then extracts the version to ~/.zvm/versions/<version>/
# there are three types of versions:
#   * master - the master branch
#   * version - a specific version
#   * stable - not actually a version in the manifest, but means we use the latest stable version
def install(version: str, verbose: bool = False):
    # check if the version is already installed
    zvm_folder = os.path.expanduser("~/.zvm")
    if os.path.exists(os.path.join(zvm_folder, "versions", version)):
        print(c.stylize(f"Version {version} is already installed", c.fg("yellow")))
        sys.exit(1)

    manifest = get_zig_mainfest()
    true_version = version
    # if the version is stable, we need to find the latest stable version
    if version == "stable":
        # get all key,value pairs from the manifest
        all_entries = manifest.items()
        # sort the entries by the date
        sorted_entries = sorted(all_entries, key=lambda x: x[1]["date"])

        # get the last entry
        last_entry = sorted_entries[-1]
        # get the version from the last entry
        true_version = last_entry[0]

    # get the zig data for the version
    if true_version not in manifest:
        print(c.stylize(f"Version {version} does not exist", c.fg("red")))
        sys.exit(1)
    zig_data = manifest[true_version]

    # get the machine name
    machine_name = get_machine_name()
    if machine_name not in zig_data:
        # use colored
        print(c.stylize(f"No zig version for {machine_name}", c.fg("red")))
        sys.exit(1)

    # get the tarball url
    tarball = zig_data[machine_name]["tarball"]

    # Installing version <bold><blue>$version</blue></bold> (<bold><blue>$true_version</blue></bold>) <dim>$tarball</dim>
    print("Installing version", c.stylize(version, c.attr("bold"), c.fg("blue")), end=" ")
    if version != true_version:
        print(" (", c.stylize(true_version, c.attr("bold"), c.fg("blue")), ") ", end="")
    print(c.stylize(tarball, c.attr("dim")))

    web_cache = os.path.join(zvm_folder, "cache", "web")
    tarball_filename = os.path.basename(tarball)
    tarball_path = os.path.join(web_cache, tarball_filename)
    # if the cache folder doesn't exist, create it
    if not os.path.exists(web_cache):
        os.makedirs(web_cache)
    # check if the tarball is already downloaded
    do_download = True
    if os.path.exists(tarball_path):
        if verbose:
            print(f"Tarball already downloaded in cache ({tarball_path})")
        # compute the sha256 of the tarball
        sha256 = hashlib.sha256()
        with open(tarball_path, "rb") as f:
            while True:
                data = f.read(65536)
                if not data:
                    break
                sha256.update(data)
        # check if the sha256 matches
        if sha256.hexdigest() == zig_data[machine_name]["shasum"]:
            if verbose:
                print(c.stylize("Using a cached version", c.fg("green")))
            do_download = False
        else:
            if verbose:
                print("Cached version is invalid, downloading again")

    if do_download:
        # download the tarball
        total_size = int(zig_data[machine_name]["size"])
        downloaded_size = 0
        with requests.get(tarball, stream=True) as r:
            if r.status_code != 200:
                print(
                    c.stylize(
                        f"Failed to download tarball with status code {r.status_code}", c.fg("red")
                    )
                )
                sys.exit(1)

            # write the file to ~/.zvm/cache/web/<version>.tar.xz
            with open(tarball_path, "wb") as f, tqdm.tqdm(
                total=total_size, unit="B", unit_scale=True
            ) as pbar:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
                    l = len(chunk)
                    downloaded_size += l
                    pbar.update(l)
        # dim
        print(c.stylize(f"Downloaded {bytes2human(total_size)}", c.attr("dim")))

    # extract the tarball to ~/.zvm/cache/extracted/<uuid>/
    micros = int(round(time.time()))
    extract_path = os.path.join(zvm_folder, "cache", "extracted", str(micros))
    # check the tarball extension

    if tarball.endswith(".zip"):
        with zipfile.ZipFile(tarball_path, "r") as zip_ref:
            zip_ref.extractall(extract_path)
    else:
        with tarfile.open(tarball_path) as tar_ref:
            tar_ref.extractall(extract_path)
    # make sure there is only one folder in the extracted folder
    extracted_folders = os.listdir(extract_path)
    if len(extracted_folders) != 1:
        print(
            c.stylize(
                f"Invalid tarball, expected 1 folder, got {len(extracted_folders)}", c.fg("red")
            )
        )
        sys.exit(1)
    # move the extracted folder to ~/.zvm/versions/<version>/
    extracted_folder = os.path.join(extract_path, extracted_folders[0])
    version_path = os.path.join(zvm_folder, "versions", true_version)
    # make sure ~/.zvm/versions exists
    if not os.path.exists(os.path.join(zvm_folder, "versions")):
        os.makedirs(os.path.join(zvm_folder, "versions"))
    os.rename(extracted_folder, version_path)
    # remove the extracted folder
    os.rmdir(extract_path)

    # create a .zvm_version file in ~/.zvm/versions/<version>/ containing the true version
    with open(os.path.join(zvm_folder, "versions", version, ".zvm_version"), "w") as f:
        f.write(zig_data["version"])

    print(c.stylize(f"Successfully installed version {true_version}", c.fg("green")))


def update(version: str):
    """
    Updates a version. This only works for "stable" and "master".
    """
    if version not in ["stable", "master"]:
        print(c.stylize("Only stable and master can be updated", c.fg("yellow")))
        sys.exit(1)

    # get the manifest
    manifest = get_zig_mainfest()

    zvm_folder = os.path.expanduser("~/.zvm")
    # get the current version
    current_version: str
    zvm_version_file = os.path.join(zvm_folder, "versions", version, ".zvm_version")
    if not os.path.exists(zvm_version_file):
        print(c.stylize(f"Version {version} is not installed", c.fg("red")))
        sys.exit(1)
    with open(zvm_version_file) as f:
        current_version = f.read()

    version_to_install: Optional[str] = None
    if version == "stable":
        # get all key,value pairs from the manifest
        all_entries = manifest.items()
        # sort the entries by the date
        sorted_entries = sorted(all_entries, key=lambda x: x[1]["date"])

        # get the last entry
        last_entry = sorted_entries[-1]
        # get the version from the last entry
        new_version = last_entry[0]
        # check the new version is newer than the current version
        if new_version == current_version:
            print("already up to date")
            sys.exit(0)
        version_to_install = new_version
    elif version == "master":
        # check that the new version is newer than the current version
        new_version = manifest["master"]["version"]
        version_to_install = "master"
        if new_version == current_version:
            print(c.stylize("Already up to date", c.fg("yellow")))
            sys.exit(0)

        # delete the current version
    shutil.rmtree(os.path.join(zvm_folder, "versions", version))

    # install the new version
    install(version_to_install)


def uninstall(version: str):
    """
    Uninstalls a version.
    """
    zvm_folder = os.path.expanduser("~/.zvm")
    # check if the version is installed
    if not os.path.exists(os.path.join(zvm_folder, "versions", version)):
        print(c.stylize(f"Version {version} is not installed", c.fg("yellow")))
        sys.exit(1)

    # delete the version
    shutil.rmtree(os.path.join(zvm_folder, "versions", version))
    print(c.stylize(f"Successfully uninstalled version {version}", c.fg("green")))


def get_current_version() -> Optional[str]:
    """
    Gets the current version.
    """
    zvm_folder = os.path.expanduser("~/.zvm")
    current = os.path.join(zvm_folder, "versions", "current")
    if not os.path.exists(current):
        return None
    # get symlink target
    dest = os.readlink(current)
    # get the version
    version = os.path.basename(dest)
    return version


def list_versions():
    """
    Lists all installed versions.
    """
    zvm_folder = os.path.expanduser("~/.zvm")
    # check if the versions folder exists
    if not os.path.exists(os.path.join(zvm_folder, "versions")):
        print(c.stylize("No versions installed", c.fg("yellow")))
        sys.exit(0)

    # get all versions
    versions = os.listdir(os.path.join(zvm_folder, "versions"))

    # get current version
    current_version = get_current_version()

    print(c.stylize("Installed versions:", c.attr("bold")))

    # only keep dirs that are not symlinks and that contain a .zvm_version file
    # print the versions
    for v in versions:
        full_v_path = os.path.join(zvm_folder, "versions", v)
        if os.path.islink(full_v_path):
            continue
        if not os.path.exists(os.path.join(full_v_path, ".zvm_version")):
            continue
        true_version = None
        with open(os.path.join(full_v_path, ".zvm_version")) as f:
            true_version = f.read()
        version_str = f"  {v}"
        if v != true_version:
            version_str += f" ({true_version})"
        if v == current_version:
            print(c.stylize(f"  - {version_str} (current)", c.fg("green")))
        else:
            print(f"  - {version_str}")


def use(version: str, global_: bool = True):
    """
    Uses a version.
    """
    if global_:
        local_zvm_folder = os.path.expanduser("~/.zvm")
        # check if the version is installed
        if not os.path.exists(os.path.join(local_zvm_folder, "versions", version)):
            print(f"version {version} is not installed")
            sys.exit(1)

        # get the current version
        current_version = get_current_version()

        # delete the current symlink if it exists
        if current_version is not None:
            os.remove(os.path.join(local_zvm_folder, "versions", "current"))
        # create a new symlink
        os.symlink(
            os.path.join(local_zvm_folder, "versions", version),
            os.path.join(local_zvm_folder, "versions", "current"),
        )
        print("Now using version", c.stylize(version, c.fg("green"), c.attr("bold")))
    else:
        # create a symlink to the selected version in `cwd`/.zvm/zig_sdk
        cwd = os.getcwd()
        local_zvm_folder = os.path.join(cwd, ".zvm")
        zvm_folder = os.path.expanduser("~/.zvm")
        # check if the version is installed
        if not os.path.exists(os.path.join(zvm_folder, "versions", version)):
            print(c.stylize(f"Version {version} is not installed", c.fg("yellow")))
            sys.exit(1)

        # check if the .zvm folder exists
        if not os.path.exists(local_zvm_folder):
            os.mkdir(local_zvm_folder)

        # symlink `cwd`/.zvm/zig_sdk to ~/.zvm/versions/version
        # check if the symlink already exists
        zig_sdk_local_path = os.path.join(local_zvm_folder, "zig_sdk")
        if os.path.exists(zig_sdk_local_path):
            os.remove(zig_sdk_local_path)
        os.symlink(
            os.path.join(zvm_folder, "versions", version),
            zig_sdk_local_path,
            target_is_directory=True,
        )
        print("Now using version", c.stylize(version, c.fg("green"), c.attr("bold")))


def spawn_zig(version: str, args: List[str]):
    """
    Spawns a zig process.
    """
    zvm_folder = os.path.expanduser("~/.zvm")
    # check if the version is installed
    if not os.path.exists(os.path.join(zvm_folder, "versions", version)):
        print(c.stylize(f"Version {version} is not installed", c.fg("red")))
        sys.exit(1)

    print(c.stylize(f"Spawning version {version}", c.fg("green")))
    # get the zig executable path
    zig_path = os.path.join(zvm_folder, "versions", version, "zig")
    # spawn the zig process
    os.execv(zig_path, [zig_path] + args)


def list_online_versions():
    """
    Lists all online versions.
    """
    # get the manifest
    manifest = get_zig_mainfest()
    # get all key,value pairs from the manifest
    all_entries = manifest.items()
    # sort the entries by the date
    sorted_entries = sorted(all_entries, key=lambda x: x[1]["date"])

    print(c.stylize("Online versions:", c.attr("bold")))
    # print the versions
    for v in sorted_entries:
        version = v[0]
        date = v[1]["date"]
        if version == "master":
            print(f"  - {version} - {manifest[version]['version']} - {date}")
        else:
            print(f"  - {version} ({date})")


def clear_cache():
    """
    Clears the cache.
    """
    zvm_folder = os.path.expanduser("~/.zvm")
    cache_folder = os.path.join(zvm_folder, "cache")
    # check if the cache folder exists
    if not os.path.exists(cache_folder):
        print(c.stylize("Cache already empty", c.fg("yellow")))
        sys.exit(0)
    # delete the cache folder
    shutil.rmtree(cache_folder)
    print(c.stylize("Successfully cleared cache", c.fg("green")))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Zig version manager")
    subparsers = parser.add_subparsers(dest="command")

    # install command
    install_parser = subparsers.add_parser("install")
    install_parser.add_argument("version", help="the version to install")
    install_parser.add_argument("--verbose", action="store_true")

    # update command
    update_parser = subparsers.add_parser("update")
    update_parser.add_argument("version", help="the version to update")

    # uninstall command
    uninstall_parser = subparsers.add_parser("uninstall")
    uninstall_parser.add_argument("version", help="the version to uninstall")

    # list command
    list_parser = subparsers.add_parser("list")
    list_parser.add_argument("--online", action="store_true", help="list online versions")

    # use command
    use_parser = subparsers.add_parser("use")
    use_parser.add_argument("version", help="the version to use")
    use_parser.add_argument(
        "-g", "--global", action="store_true", help="use globally", dest="global_"
    )

    # spawn command
    spawn_parser = subparsers.add_parser("spawn")
    spawn_parser.add_argument("version", help="the version to spawn")
    spawn_parser.add_argument("args", nargs=argparse.REMAINDER, help="the arguments to pass to zig")

    # cache command
    cache_parser = subparsers.add_parser("cache")
    cache_parser.add_argument("action", help="the action to perform", choices=["clear"])

    # help command
    help_parser = subparsers.add_parser("help")

    args = parser.parse_args()

    if args.command == "install":
        install(args.version, verbose=args.verbose)
    elif args.command == "update":
        update(args.version)
    elif args.command == "uninstall":
        uninstall(args.version)
    elif args.command == "list":
        if args.online:
            list_online_versions()
        else:
            list_versions()
    elif args.command == "use":
        use(args.version, global_=args.global_)
    elif args.command == "help":
        parser.print_help()
    elif args.command == "spawn":
        spawn_zig(args.version, args.args)
    elif args.command == "cache":
        if args.action == "clear":
            clear_cache()
    else:
        parser.print_help()
