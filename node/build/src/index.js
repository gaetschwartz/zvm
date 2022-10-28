"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
/* eslint-disable no-process-exit */
const axios_1 = require("axios");
const chalk_1 = require("chalk");
const child_process_1 = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const fse = require("fs-extra");
const os = require("os");
const path = require("path");
const proc = require("process");
const process_1 = require("process");
const yargs = require("yargs");
// get https://ziglang.org/download/index.json
const zigLsJsonUrl = 'https://ziglang.org/download/index.json';
// const identifierRegex = /^(?<cpuArch>x86_64|aarch64)-(?<platform>\w+)$/;
// fetches and parses the data into an object
async function fetchZigJson() {
    const response = await axios_1.default.get(zigLsJsonUrl);
    const index = response.data;
    // for entries in index
    for (const [key, value] of Object.entries(index)) {
        // if entry is master
        value.version = key;
    }
    return index;
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
async function downloadAndInstall(release) {
    // download to temp dir
    const cpuArch = getCpuArch();
    const platform = getPlatform();
    const zvmPath = path.join(os.homedir(), '.zvm');
    const versionsPath = path.join(zvmPath, 'versions');
    const cachePath = path.join(zvmPath, 'cache');
    if (!fs.existsSync(cachePath)) {
        fs.mkdirSync(cachePath, { recursive: true });
    }
    const tarballPath = path.join(cachePath, path.basename(release.src.tarball));
    const source = release[`${cpuArch}-${platform}`];
    const tarballUrl = source.tarball;
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
                const percent = Math.round((downloaded / Number(source.size)) * 100);
                process_1.stdout.write(`Downloaded ${percent}%  \r`);
            });
        });
        console.log('Downloaded', tarballPath);
        // extract to temp dir
        const folderName = `${release.version}`;
        const thisVersionPath = path.join(versionsPath, folderName);
        if (fs.existsSync(thisVersionPath)) {
            fs.rmSync(thisVersionPath, { recursive: true });
        }
        fs.mkdirSync(thisVersionPath, { recursive: true });
        const extractPath = path.join(os.tmpdir(), 'zvm', folderName);
        if (fs.existsSync(extractPath)) {
            fs.rmSync(extractPath, { recursive: true });
        }
        fs.mkdirSync(extractPath, { recursive: true });
        console.log('Extracting', tarballPath, 'to', extractPath);
        // run `tar -xvzf tarballPath -C extractPath`
        const res = (0, child_process_1.spawn)('tar', ['-xzf', tarballPath, '-C', extractPath], {
            stdio: 'inherit',
        });
        if (res.exitCode !== 0) {
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
        console.log('Copying', topFolderExtractPath, 'to', thisVersionPath);
        // recursively copy all files from topFolderExtractPath to versionPath
        await fse.copy(topFolderExtractPath, thisVersionPath, { recursive: true });
    }
}
async function main() {
    // use yargs to parse args
    const argv = await yargs
        .command('list', 'List installed versions', {})
        .command('install <version>', 'Install a version', {
        version: {
            type: 'string',
            default: 'stable',
        },
    })
        .command('use <version>', 'Use a version', {
        version: {
            type: 'string',
        },
    })
        .command('uninstall <version>', 'Uninstall a version', {
        version: {
            type: 'string',
        },
    })
        .command('cache <command>', 'Cache commands', yargs => {
        return yargs.command('clear', 'Clear the cache', {});
    })
        .command('spawn <version> [command..]', 'Run the provided command with the zig version', {
        version: {
            type: 'string',
        },
        command: {
            type: 'string',
        },
    })
        .option('verbose', {
        type: 'boolean',
        default: false,
    })
        .help()
        .alias('help', 'h')
        .scriptName('zvm')
        .version(false).argv;
    if (argv.verbose) {
        console.log('argv', argv);
    }
    const command = argv._[0];
    if (command === 'list') {
        await list();
    }
    else if (command === 'install') {
        await install(argv.version);
    }
    else if (command === 'use') {
        await use(argv.version);
    }
    else if (command === 'uninstall') {
        await uninstall(argv.version);
    }
    else if (command === 'spawn') {
        await spawn_cmd(argv.version, argv.command.join(' '));
    }
    else if (command === 'cache') {
        // check command
        const cacheCommand = argv._[1];
        if (cacheCommand === 'clear') {
            await cacheClear();
        }
        else {
            console.error('Unknown cache command', cacheCommand);
            process.exit(1);
        }
    }
    else {
        console.error('Unknown command', command);
        process.exit(1);
    }
}
async function list() {
    const zigDir = path.join(os.homedir(), '.zvm');
    const versionsPath = path.join(zigDir, 'versions');
    const versions = fs.readdirSync(versionsPath);
    const currentPath = path.join(zigDir, 'versions', 'current');
    let current = '';
    if (fs.existsSync(currentPath)) {
        current = fs.readlinkSync(currentPath);
    }
    console.log('Current:', current, '\n');
    // only keep the folder name of the current version
    current = path.basename(current);
    for (const version of versions) {
        if (version === 'current') {
            continue;
        }
        if (version === current) {
            console.log(version, '(current)');
        }
        else {
            console.log(version);
        }
    }
}
async function use(version) {
    const zigDir = path.join(os.homedir(), '.zvm');
    const versionsPath = path.join(zigDir, 'versions');
    const versionPath = path.join(versionsPath, version);
    if (!fs.existsSync(versionPath)) {
        console.error('Version', version, 'not installed');
        process.exit(1);
    }
    const currentPath = path.join(zigDir, 'versions', 'current');
    if (fs.existsSync(currentPath)) {
        fs.unlinkSync(currentPath);
    }
    fs.symlinkSync(versionPath, currentPath);
}
async function uninstall(version) {
    const zigDir = path.join(os.homedir(), '.zvm');
    const versionsPath = path.join(zigDir, 'versions');
    const versionPath = path.join(versionsPath, version);
    if (!fs.existsSync(versionPath)) {
        console.error('Version', version, 'not installed');
        process.exit(1);
    }
    fs.rmSync(versionPath, { recursive: true });
    console.log(chalk_1.default.green('✅ Uninstalled version', chalk_1.default.bold(version), '.'));
}
async function spawn_cmd(version, command) {
    console.log('Spawning', command, 'with zig version', version, '\n');
    const zvmDir = path.join(os.homedir(), '.zvm');
    const versionsPath = path.join(zvmDir, 'versions');
    const versionPath = path.join(versionsPath, version);
    if (!fs.existsSync(versionPath)) {
        console.error('Version', version, 'not installed');
        process.exit(1);
    }
    // if we are in windows, we need to use the .exe
    const exe = os.platform() === 'win32' ? '.exe' : '';
    const zigPath = path.join(versionPath, 'zig' + exe);
    const res = (0, child_process_1.spawn)(zigPath + ' ' + command, {
        shell: true,
        stdio: 'inherit',
    });
    await new Promise((resolve, reject) => {
        res.on('close', resolve);
        res.on('error', reject);
    });
}
async function install(channelOrVersion) {
    // can be either master, stable, or a version number
    const versions = await fetchZigJson();
    const zigDir = path.join(os.homedir(), '.zvm');
    const versionsPath = path.join(zigDir, 'versions');
    if (!fs.existsSync(versionsPath)) {
        fs.mkdirSync(versionsPath, { recursive: true });
    }
    let version = '';
    if (channelOrVersion === 'master') {
        version = 'master';
    }
    else if (channelOrVersion === 'stable') {
        // latest stable version
        // sort all versions by date and take the latest
        const sortedVersions = Object.keys(versions).sort((a, b) => {
            const aDate = new Date(versions[a].date);
            const bDate = new Date(versions[b].date);
            return bDate.getTime() - aDate.getTime();
        });
        version = sortedVersions[0];
    }
    else {
        // assume it is a version number
        version = channelOrVersion;
    }
    if (!versions[version]) {
        console.error('Version', version, 'not found');
        process.exit(1);
    }
    const versionPath = path.join(versionsPath, version);
    if (fs.existsSync(versionPath)) {
        console.error('Version', version, 'already installed');
        process.exit(1);
    }
    const release = versions[version];
    await downloadAndInstall(release);
}
async function cacheClear() {
    const zvmDir = path.join(os.homedir(), '.zvm');
    const cachePath = path.join(zvmDir, 'cache');
    if (fs.existsSync(cachePath)) {
        fs.rmSync(cachePath, { recursive: true });
    }
    console.log(chalk_1.default.green('Cache cleared'));
}
main();
//# sourceMappingURL=index.js.map