index=$(curl -s https://ziglang.org/download/index.json)
master=$(echo $index | jq -r '.master')
# on_macos do
#     if Hardware::CPU.arm?
#       resource "zig" do
#         url "https://ziglang.org/builds/zig-macos-aarch64-0.11.0-dev.1638+7199d7c77.tar.xz"
#         sha256 "5709c27d581988f50f5e6fd5b69d92707787e803a1d04992e290b764617664e6"
#       end
#     else
#       resource "zig" do
#         url "https://ziglang.org/builds/zig-macos-x86_64-0.11.0-dev.1638+7199d7c77.tar.xz"
#         sha256 "88d194adb2f3c1a9edbb4a24d018007d5f827a57d1d26b2d9f3459236da1b7b6"
#       end
#     end
#   end
#   on_linux do
#     if Hardware::CPU.arm?
#       resource "zig" do
#         url "https://ziglang.org/builds/zig-linux-aarch64-0.11.0-dev.1638+7199d7c77.tar.xz"
#         sha256 "b759a11993949531c692ccfc3d1a004b14df714a7a3515fe0b5c90c9a7631d61"
#       end
#     else
#       resource "zig" do
#         url "https://ziglang.org/builds/zig-linux-x86_64-0.11.0-dev.1638+7199d7c77.tar.xz"
#         sha256 "028dad5189e02b2058679b64df16e854a1c1ca0e6044b334d4f3be6e35544f07"
#       end
#     end
#   end

# We want to echo this
aarch64_macos_tarball=$(echo $master | jq -r '.["aarch64-macos"].tarball')
aarch64_macos_shasum=$(echo $master | jq -r '.["aarch64-macos"].shasum')
x86_64_macos_tarball=$(echo $master | jq -r '.["x86_64-macos"].tarball')
x86_64_macos_shasum=$(echo $master | jq -r '.["x86_64-macos"].shasum')
aarch64_linux_tarball=$(echo $master | jq -r '.["aarch64-linux"].tarball')
aarch64_linux_shasum=$(echo $master | jq -r '.["aarch64-linux"].shasum')
x86_64_linux_tarball=$(echo $master | jq -r '.["x86_64-linux"].tarball')
x86_64_linux_shasum=$(echo $master | jq -r '.["x86_64-linux"].shasum')
cat <<EOF | xargs -0 echo
on_macos do
    if Hardware::CPU.arm?
      resource "zig" do
        url "$aarch64_macos_tarball"
        sha256 "$aarch64_macos_shasum"
      end
    else
      resource "zig" do
        url "$x86_64_macos_tarball"
        sha256 "$x86_64_macos_shasum"
      end
    end
  end
  on_linux do
    if Hardware::CPU.arm?
      resource "zig" do
        url "$aarch64_linux_tarball"
        sha256 "$aarch64_linux_shasum"
      end
    else
      resource "zig" do
        url "$x86_64_linux_tarball"
        sha256 "$x86_64_linux_shasum"
      end
    end
  end
EOF
