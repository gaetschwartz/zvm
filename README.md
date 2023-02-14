![Ci badge](https://github.com/gaetschwartz/zvm/actions/workflows/master.yml/badge.svg)

Zig Version Manager (zvm) is a simple yet powerfulto manage multiple versions of the Zig programming language.

## Installation

### Homebrew
```
brew tap gaetschwartz/zvm
brew install zvm
```

### Scoop
```powershell
scoop bucket add zvm https://github.com/gaetschwartz/scoop-zvm
scoop install zvm
```
*Note: Due to [an issue with Expand-Archive](https://github.com/PowerShell/Microsoft.PowerShell.Archive/issues/32) on Windows it is recommended to install `7zip` and add it to your PATH. Zvm will automatically use it if it is available.
This can be done by running `scoop install 7zip`.*

### Manually

Choose your platform and download the latest release [here](https://github.com/gaetschwartz/zvm/releases/latest).

Add the binary to your path.

## Usage

### Install a new version

```
# specific versons can be installed
zvm install 0.10.1

# as well as channels (master, stable)
zvm install master
```

### List installed versions

```
zvm list
```

### Use a specific version

You can use a version globally or for the current directory.

```bash
# symlink the selected version to ~/.zvm/default/
zvm use 0.10.1 --global

# symlink the selected version to .zvm/
zvm use 0.10.1
```
You then can point to it in VSCode or your IDE of choice.
You can also choose to use a local git repository of zig as a version.

```bash
zvm config set git_dir_path /path/to/zig/repo
zvm use git
```

### Run a command with a specific version of zig

```
zvm spawn 0.10.1 zig build
```

### Run a command using the selected version of zig

```
zvm zig build
```

## Contributing

Contributions, issues and feature requests are welcome!

### Building from source

```
git clone https://github.com/gaetschwartz/zvm.git
git submodule update --init --recursive
cd zvm
zig build
```
