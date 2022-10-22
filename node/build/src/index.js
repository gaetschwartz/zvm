"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
/* eslint-disable no-process-exit */
const axios_1 = require("axios");
const child_process_1 = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const fse = require("fs-extra");
const os = require("os");
const proc = require("process");
const process_1 = require("process");
const path = require("path");
// get https://ziglang.org/download/index.json
const zigLsJsonUrl = 'https://ziglang.org/download/index.json';
// const identifierRegex = /^(?<cpuArch>x86_64|aarch64)-(?<platform>\w+)$/;
// fetches and parses the data into an object
async function loadZigLsJson() {
    const response = await axios_1.default.get(zigLsJsonUrl);
    return response.data;
}
// returns CPU arch
// x86_64 or aarch64
function getCpuArch() {
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
function getPlatform() {
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
    const channel = (proc.argv[2] || 'stable');
    const zigIndex = await loadZigLsJson();
    // console.log(zigIndex);
    const cpuArch = getCpuArch();
    const platform = getPlatform();
    const identifier = `${cpuArch}-${platform}`;
    for (const [version, release] of Object.entries(zigIndex)) {
        release.version = version;
    }
    const versions = Object.values(zigIndex).filter(v => v.version !== zigIndex.master.version);
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
    const mostRecentRelease = mostRecentVersion[identifier];
    const masterRelease = masterVersion[identifier];
    const release = channel === 'stable' ? mostRecentRelease : masterRelease;
    console.log('most recent release', mostRecentRelease);
    console.log('master release', masterRelease);
    const tarballUrl = release.tarball;
    const size = release.size;
    // download to temp dir
    const tarballPath = path.join(os.tmpdir(), `zig-${channel}-${cpuArch}-${platform}.tar.xz`);
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
        }
        else {
            console.log('Existing file does not match shasum, deleting');
            fs.rmSync(tarballPath);
        }
    }
    if (doDownload) {
        const tarballStream = fs.createWriteStream(tarballPath);
        const response = await axios_1.default.get(tarballUrl, {
            responseType: 'stream',
        });
        // show progress
        let downloaded = 0;
        await new Promise((resolve, reject) => {
            response.data.on('end', resolve);
            response.data.on('error', reject);
            response.data.pipe(tarballStream);
            response.data.on('data', (chunk) => {
                downloaded += chunk.length;
                const percent = Math.round((downloaded / Number(size)) * 100);
                process_1.stdout.write(`Downloaded ${percent}%  \r`);
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
        fs.rmSync(versionPath, { recursive: true });
    }
    fs.mkdirSync(versionPath, { recursive: true });
    const extractPath = path.join(os.tmpdir(), 'zvm', folderName);
    if (fs.existsSync(extractPath)) {
        fs.rmSync(extractPath, { recursive: true });
    }
    fs.mkdirSync(extractPath, { recursive: true });
    console.log('Extracting', tarballPath, 'to', extractPath);
    // run `tar -xvzf tarballPath -C extractPath`
    const res = (0, child_process_1.spawn)('tar -xvzf ' + tarballPath + ' -C ' + extractPath, {
        shell: true,
    });
    let out = '';
    let err = '';
    await new Promise((resolve, reject) => {
        res.on('close', resolve);
        res.on('error', reject);
        res.stdout.on('data', (data) => {
            const s = data.toString();
            out += s;
            process_1.stdout.write(s + '\r'.repeat(proc.stdout.columns - s.length));
        });
        res.stderr.on('data', (data) => {
            err += data.toString();
            process_1.stderr.write(data.toString());
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
    await fse.copy(topFolderExtractPath, versionPath, { recursive: true });
    // create link from $(zigDir)/versions/current to $(zigDir)/versions/$(version)
    const currentPath = path.join(zigDir, 'versions', 'current');
    if (fs.existsSync(currentPath)) {
        fs.unlinkSync(currentPath);
    }
    fs.symlinkSync(versionPath, currentPath);
}
main();
//# sourceMappingURL=index.js.map