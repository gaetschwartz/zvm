![Ci badge](https://github.com/gaetschwartz/zvm/actions/workflows/master.yml/badge.svg)

Zig Version Manager (`zvm`) is a simple yet powerful tool to manage multiple versions of the Zig programming language.

## 📚 Table of Contents

- [✨ Features](#-features)
- [📥 Installation](#-installation)
  - [🍺 Homebrew](#-homebrew)
  - [🍨 Scoop](#-scoop)
  - [⚙️ Manually](#%EF%B8%8F-manually)
- [🧠 Auto-completion](#-auto-completion)
- [📝 Differences with other Zig version managers](#-differences-with-other-zig-version-managers)
  - [Zigup](#zigup)
- [🫂 Contributing](#-contributing)

## ✨ Features

#### 📦 Install multiple versions of Zig
```zsh
# specific versons can be installed
zvm install 0.10.1
```
```zsh
# as well as channels (master, stable)
zvm install master
# channels can be upgraded to the latest version
zvm upgrade master
```

#### 🚀 Switch between versions
```zsh
# switch to a specific version globally (~/.zvm/default)
zvm use 0.10.1 --global
```
```zsh
# or for the current directory (./.zvm/)
zvm use 0.10.1
```
```zsh
# a local git repository can also be used
zvm config set git_dir_path /path/to/zig/repo
zvm use git
```
#### 📝 Run a command with a specific version of Zig
```zsh
# with the selected version
zvm zig build -Doptimize=ReleaseFast
```
```zsh
# or with a specific version
zvm spawn 0.10.1 zig build -Doptimize=ReleaseFast
```

## 📥 Installation

### 🍺 Homebrew
```
brew tap gaetschwartz/zvm
brew install zvm
```

### 🍨 Scoop
```powershell
scoop bucket add zvm https://github.com/gaetschwartz/scoop-zvm
scoop install zvm
```
*Note: Due to [an issue with Expand-Archive](https://github.com/PowerShell/Microsoft.PowerShell.Archive/issues/32) on Windows it is recommended to install `7zip` and add it to your PATH. Zvm will automatically use it if it is available.
This can be done by running `scoop install 7zip`.*

### ⚙️ Manually

Choose your platform and download the latest release [here](https://github.com/gaetschwartz/zvm/releases/latest).

Add the binary to your path.

## 🧠 Auto-completion

Auto-completion is available for `zsh` and `powershell`. It is installed automatically when using the Homebrew.

### Powershell

Add this to your $PROFILE to enable auto-completion for powershell.

```powershell
Invoke-Expression ((zvm completions --shell=powershell) -join "`n")
```

## 📝 Differences with other Zig version managers

### Zigup

[Zigup](https://github.com/marler8997/zigup) is a great tool to install Zig and manage multiple versions of Zig. However, it is pretty much limited to managing the different versions of Zig. 

Zvm on the counterpart aims to be a more complete Zig version manager. It allows to run a command with a specific version of Zig, to switch between versions (globally or for the current directory) and to use a local git repository as a Zig version.
## 🫂 Contributing

Contributions, issues and feature requests are welcome!

### Building from source

```
git clone --recurse-submodules -j8 https://github.com/gaetschwartz/zvm.git
cd zvm
zig build -Doptimize=ReleaseFast
```
