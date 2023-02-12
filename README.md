## zvm

#### ✨ A simple yet powerful version manager for zig

### Installation

#### Homebrew
```
brew tap gaetschwartz/zvm
brew install zvm
```

#### Scoop
```powershell
scoop bucket add zvm https://github.com/gaetschwartz/scoop-bucket.git
scoop install zvm
```

#### Manually

Choose your platform and download the latest release [here](https://github.com/gaetschwartz/zvm/releases/latest).

Add the binary to your path.

### Usage

#### Install a new version

```
zvm install 0.10.1
```

#### List installed versions

```
zvm list
```

#### Use a specific version

##### Globally

```
zvm use 0.10.1 --global
```

##### For the current directory
```
zvm use 0.10.1
```

This will create a symlink in your current directory at `.zvm/zig` that points to the zig binary of the version you specified.

You then can point to it in VSCode or your IDE of choice.

#### Run a command with a specific version of zig

```
zvm spawn 0.10.1 zig build
```

#### Run the currently active version of zig

```
zvm zig build
```

#### Upgrade a currently installed channel

```
zvm upgrade master
```

#### More help

Use `zvm --help` for more info.

### Contributing

Contributions, issues and feature requests are welcome!

#### Building from source

```
git clone https://github.com/gaetschwartz/zvm.git
git submodule update --init --recursive
cd zvm
zig build
```