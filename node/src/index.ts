/* eslint-disable no-process-exit */
import axios from 'axios';
import {spawn} from 'child_process';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as fse from 'fs-extra';
import * as os from 'os';
import * as proc from 'process';
import {stderr, stdout} from 'process';
import path = require('path');
// get https://ziglang.org/download/index.json

const zigLsJsonUrl = 'https://ziglang.org/download/index.json';

// release:
// {"version": "0.10.0-dev.4474+b41b35f57",
// "date": "2022-10-20",
// "docs": "https://ziglang.org/documentation/master/",
// "stdDocs": "https://ziglang.org/documentation/master/std/",
// "src": {
// "tarball": "https://ziglang.org/builds/zig-0.10.0-dev.4474+b41b35f57.tar.xz",
// "shasum": "f7c09406c29ea95bd31b9811ccb9b1fe58f587ce139a613ce026118fe92361a6",
// "size": "15936344"
// },
// "x86_64-freebsd": {
// "tarball": "https://ziglang.org/builds/zig-freebsd-x86_64-0.10.0-dev.4474+b41b35f57.tar.xz",
// "shasum": "6df41f21161d6a02aaed66bffdf6ebd1f0fd9076aa5065aa699e185975ef3081",
// "size": "41067660"
// },
// "x86_64-macos": {
// "tarball": "https://ziglang.org/builds/zig-macos-x86_64-0.10.0-dev.4474+b41b35f57.tar.xz",
// "shasum": "e3041264101e160b497a22cea35fe8aafa4eaed2cd35d67ec54660d944e35f8d",
// "size": "44159408"
// },
// "aarch64-macos": {
// "tarball": "https://ziglang.org/builds/zig-macos-aarch64-0.10.0-dev.4474+b41b35f57.tar.xz",
// "shasum": "bc0c2dbb8bf065e4301bfe37eed9e0523068f5c7a634d5671ab4fb4834e8e6f2",
// "size": "41018596"
// },
// "x86_64-windows": {
// "tarball": "https://ziglang.org/builds/zig-windows-x86_64-0.10.0-dev.4474+b41b35f57.zip",
// "shasum": "8b19acd57b7d823bac972ca669437447c1aa2fec146846cd839fc24b553a7a8f",
// "size": "69320359"
// },
// "x86_64-linux": {
// "tarball": "https://ziglang.org/builds/zig-linux-x86_64-0.10.0-dev.4474+b41b35f57.tar.xz",
// "shasum": "2230bfd4af23dbc59c7e7e7e4baf5def27450ad89e7a74a638fa6b44124eca2f",
// "size": "44297204"
// },
// "aarch64-linux": {
// "tarball": "https://ziglang.org/builds/zig-linux-aarch64-0.10.0-dev.4474+b41b35f57.tar.xz",
// "shasum": "bdde08dc60d6ad0949d58992fcd408b05a4b2acd8f5549b00e1a807866bf517b",
// "size": "37453380"
// }}

interface ZigReleaseSource {
  tarball: string;
  shasum: string;
  size: string;
}

interface ZigRelease {
  version: string | undefined;
  date: string;
  docs: string;
  stdDocs: string;
  src: ZigReleaseSource;
  bootstrap: ZigReleaseSource | null;
  [key: string]: ZigReleaseSource | unknown;
}

interface ZigIndex {
  [key: string]: ZigRelease;
}

// const identifierRegex = /^(?<cpuArch>x86_64|aarch64)-(?<platform>\w+)$/;

// fetches and parses the data into an object
async function loadZigLsJson() {
  const response = await axios.get(zigLsJsonUrl);
  return response.data as ZigIndex;
}

// returns CPU arch
// x86_64 or aarch64
function getCpuArch(): 'x86_64' | 'aarch64' {
  const arch = proc.arch;
  switch (arch) {
    case 'arm64':
      return 'aarch64';
    case 'x64':
      return 'x86_64';
    default:
      return 'x86_64';
  }
}

function getPlatform(): string {
  const platform = proc.platform;
  switch (platform) {
    case 'darwin':
      return 'macos';
    case 'linux':
      return 'linux';
    case 'win32':
      return 'windows';
    case 'freebsd':
      return 'freebsd';
    default:
      return platform;
  }
}

async function main() {
  const channel: 'stable' | 'master' = (proc.argv[2] || 'stable') as
    | 'stable'
    | 'master';

  const zigIndex = await loadZigLsJson();
  // console.log(zigIndex);
  const cpuArch = getCpuArch();
  const platform = getPlatform();
  const identifier = `${cpuArch}-${platform}`;
  for (const [version, release] of Object.entries(zigIndex)) {
    release.version = version;
  }
  const versions: ZigRelease[] = Object.values(zigIndex).filter(
    v => v.version !== zigIndex.master.version
  );
  // sort by date
  versions.sort((a, b) => {
    const aDate = new Date(a.date);
    const bDate = new Date(b.date);
    return aDate.getTime() - bDate.getTime();
  });
  console.log('Versions:', versions.length);
  const mostRecentVersion = versions[versions.length - 1];
  const masterVersion = zigIndex.master;
  const version = channel === 'stable' ? mostRecentVersion : masterVersion;

  const mostRecentRelease = mostRecentVersion[identifier] as ZigReleaseSource;
  const masterRelease = masterVersion[identifier] as ZigReleaseSource;
  const release = channel === 'stable' ? mostRecentRelease : masterRelease;

  console.log('most recent release', mostRecentRelease);
  console.log('master release', masterRelease);

  const tarballUrl = release.tarball;
  const size = release.size;

  // download to temp dir
  const tarballPath = path.join(
    os.tmpdir(),
    `zig-${channel}-${cpuArch}-${platform}.tar.xz`
  );
  console.log('Downloading', tarballUrl, 'to', tarballPath);
  let doDownload = true;
  if (fs.existsSync(tarballPath)) {
    console.log('Already downloaded');
    // check sha256
    const content = await fs.promises.readFile(tarballPath);
    const shasum = crypto.createHash('sha256').update(content).digest('hex');
    if (shasum === release.shasum) {
      console.log('Already downloaded and verified');
      doDownload = false;
    } else {
      console.log('Existing file does not match shasum, deleting');
      fs.rmSync(tarballPath);
    }
  }
  if (doDownload) {
    const tarballStream = fs.createWriteStream(tarballPath);
    const response = await axios.get(tarballUrl, {
      responseType: 'stream',
    });
    // show progress
    let downloaded = 0;
    await new Promise((resolve, reject) => {
      response.data.on('end', resolve);
      response.data.on('error', reject);
      response.data.pipe(tarballStream);
      response.data.on('data', (chunk: Buffer) => {
        downloaded += chunk.length;
        const percent = Math.round((downloaded / Number(size)) * 100);
        stdout.write(`Downloaded ${percent}%  \r`);
      });
    });

    console.log('Downloaded', tarballPath);
  }

  // extract to temp dir
  const folderName = `${version.version}`;

  // move to zig dir
  const zigDir = path.join(os.homedir(), '.zvm');
  // check if zig dir exists
  if (!fs.existsSync(zigDir)) {
    fs.mkdirSync(zigDir);
  }
  const versionPath = path.join(zigDir, 'versions', folderName);
  if (fs.existsSync(versionPath)) {
    fs.rmSync(versionPath, {recursive: true});
  }
  fs.mkdirSync(versionPath, {recursive: true});
  const extractPath = path.join(os.tmpdir(), 'zvm', folderName);
  if (!fs.existsSync(extractPath)) {
    fs.mkdirSync(extractPath, {recursive: true});
  }
  console.log('Extracting', tarballPath, 'to', extractPath);
  // run `tar -xvzf tarballPath -C extractPath`
  const res = spawn('tar -xvzf ' + tarballPath + ' -C ' + extractPath, {
    shell: true,
  });
  let out = '';
  let err = '';
  await new Promise((resolve, reject) => {
    res.on('close', resolve);
    res.on('error', reject);
    res.stdout.on('data', (data: Buffer) => {
      out += data.toString();
      stdout.write(data.toString());
    });
    res.stderr.on('data', (data: Buffer) => {
      err += data.toString();
      stderr.write(data.toString());
    });
  });
  if (res.exitCode !== 0) {
    console.error(err);
    console.error('Error extracting', tarballPath, 'to', extractPath);
    process.exit(1);
  }

  console.log('Extracted', tarballPath, 'to', extractPath);
  // get the top level folder from the tarball
  const files = fs.readdirSync(extractPath);
  if (files.length !== 1) {
    console.error('Expected 1 top level folder in tarball');
    process.exit(1);
  }
  const topFolder = files[0];
  // copy this folder to versionPath
  const topFolderExtractPath = path.join(extractPath, topFolder);
  console.log('Copying', topFolderExtractPath, 'to', versionPath);
  // recursively copy all files from topFolderExtractPath to versionPath
  await fse.copy(topFolderExtractPath, versionPath, {recursive: true});
  // create link from $(zigDir)/versions/current to $(zigDir)/versions/$(version)
  const currentPath = path.join(zigDir, 'versions', 'current');
  if (fs.existsSync(currentPath)) {
    fs.unlinkSync(currentPath);
  }
  fs.symlinkSync(versionPath, currentPath);
}

main();
