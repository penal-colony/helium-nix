#!/usr/bin/env node
/*
  Helium browser update script.

  Usage:
    node update.mjs                  # Update to latest Helium release
    node update.mjs 0.13.0           # Update to a specific version

  This script:
  1. Fetches the latest Helium release from GitHub
  2. Reads chromium_version.txt and deps.ini from the release tag
  3. Updates default.nix with new version and hashes
  4. Warns if the Chromium base version changed (info.json needs manual update)
*/

import { execSync } from "child_process";
import { readFileSync, writeFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const defaultNixPath = resolve(__dirname, "default.nix");
const infoJsonPath = resolve(__dirname, "info.json");

// --- Helpers ---

function run(cmd) {
  try {
    return execSync(cmd, { encoding: "utf-8" }).trim();
  } catch (e) {
    throw e;
  }
}

function fetchJSON(url) {
  return JSON.parse(run(`curl -sf ${url}`));
}

function fetchRaw(url) {
  return run(`curl -sfL ${url}`);
}

function nixHashFile(url) {
  const tmpFile = run(`mktemp`);
  run(`curl -sfL -o ${tmpFile} ${url}`);
  const hash = run(`nix hash file --type sha256 --sri ${tmpFile}`);
  run(`rm -f ${tmpFile}`);
  return hash;
}

function nixPrefetchGitHub(owner, repo, rev) {
  // Download tarball and compute the NAR hash, then convert to SRI
  const tarballUrl = `https://github.com/${owner}/${repo}/archive/${rev}.tar.gz`;
  const base32Hash = run(`nix-prefetch-url --unpack ${tarballUrl}`);
  return run(`nix hash to-sri --type sha256 ${base32Hash}`);
}

function parseDepsIni(text) {
  const deps = {};
  let current = null;
  for (const line of text.split("\n")) {
    const section = line.match(/^\[(\w+)\]/);
    if (section) {
      current = section[1];
      deps[current] = {};
      continue;
    }
    if (!current) continue;
    const kv = line.match(/^(\w+)\s*=\s*(.+)$/);
    if (kv) deps[current][kv[1]] = kv[2].trim();
  }
  return deps;
}

function replaceInFile(content, pattern, replacement) {
  const newContent = content.replace(pattern, replacement);
  if (newContent === content) {
    console.warn(`  Warning: pattern not matched: ${pattern}`);
  }
  return newContent;
}

// --- Main ---

const targetVersion = process.argv[2];

// 1. Get Helium release info
console.log("Fetching Helium release info...");
const release = targetVersion
  ? fetchJSON(`https://api.github.com/repos/imputnet/helium/releases/tags/${targetVersion}`)
  : fetchJSON(`https://api.github.com/repos/imputnet/helium/releases/latest`);

const newHeliumVersion = release.tag_name;
console.log(`Helium version: ${newHeliumVersion}`);

// 2. Read chromium_version.txt from the tag
const chromiumVersion = fetchRaw(
  `https://raw.githubusercontent.com/imputnet/helium/${newHeliumVersion}/chromium_version.txt`
).trim();
console.log(`Chromium version: ${chromiumVersion}`);

// 3. Read deps.ini
const depsIniText = fetchRaw(
  `https://raw.githubusercontent.com/imputnet/helium/${newHeliumVersion}/deps.ini`
);
const deps = parseDepsIni(depsIniText);

// 4. Read current default.nix
let content = readFileSync(defaultNixPath, "utf-8");
const currentHelium = content.match(/heliumVersion = "([^"]+)"/)?.[1];

if (currentHelium === newHeliumVersion) {
  console.log(`Already at ${newHeliumVersion}, nothing to do.`);
  process.exit(0);
}

console.log(`Updating ${currentHelium} → ${newHeliumVersion}...\n`);

// 5. Compute hashes
console.log("Computing hashes...");
const heliumSrcHash = nixPrefetchGitHub("imputnet", "helium", newHeliumVersion);

// 5b. Resolve helium-linux version (follows {helium_version}.1 convention)
let heliumLinuxTag = null;
let heliumLinuxHash = null;
for (const suffix of [".1", ".2", ""]) {
  const candidate = `${newHeliumVersion}${suffix}`;
  try {
    const resp = fetchJSON(`https://api.github.com/repos/imputnet/helium-linux/releases/tags/${candidate}`);
    if (resp.tag_name) {
      heliumLinuxTag = candidate;
      break;
    }
  } catch {
    // tag doesn't exist, try next
  }
}
if (heliumLinuxTag) {
  heliumLinuxHash = nixPrefetchGitHub("imputnet", "helium-linux", heliumLinuxTag);
  console.log(`  helium-linux: ${heliumLinuxTag} -> ${heliumLinuxHash}`);
} else {
  console.warn(`  Warning: no helium-linux release found for ${newHeliumVersion}`);
}
console.log(`  source:  ${heliumSrcHash}`);

const onboardingVersion = deps.onboarding.version;
const onboardingUrl = deps.onboarding.url.replace("%(version)s", onboardingVersion);
const onboardingHash = nixHashFile(onboardingUrl);
console.log(`  onboarding: ${onboardingHash}`);

const ublockVersion = deps.ublock_origin.version;
const ublockUrl = deps.ublock_origin.url.replace("%(version)s", ublockVersion);
const ublockHash = nixHashFile(ublockUrl);
console.log(`  ublock: ${ublockHash}`);

const searchEnginesUrl = deps.search_engines_data.url;
const searchEnginesHash = nixHashFile(searchEnginesUrl);
console.log(`  search engines: ${searchEnginesHash}`);

// 6. Apply replacements to default.nix
console.log("\nUpdating default.nix...");

// Versions
content = replaceInFile(content,
  /heliumVersion = "[^"]*"/,
  `heliumVersion = "${newHeliumVersion}"`
);
content = replaceInFile(content,
  /chromiumVersion = "[^"]*"/,
  `chromiumVersion = "${chromiumVersion}"`
);

// Source hash
content = replaceInFile(content,
  /(heliumSrc = fetchFromGitHub \{[^}]*?hash = ")[^"]*(")/s,
  `$1${heliumSrcHash}$2`
);

// Helium-linux source (rev + hash + comment)
if (heliumLinuxTag) {
  const tagRef = fetchJSON(`https://api.github.com/repos/imputnet/helium-linux/git/ref/tags/${heliumLinuxTag}`);
  const heliumLinuxCommit = tagRef.object.sha;
  content = replaceInFile(content,
    /(helium-linux-src = fetchFromGitHub \{[\s\S]*?rev = ")[^"]*(")/,
    `$1${heliumLinuxCommit}$2`
  );
  content = replaceInFile(content,
    /(helium-linux-src = fetchFromGitHub \{[\s\S]*?hash = ")[^"]*(")/,
    `$1${heliumLinuxHash}$2`
  );
  content = replaceInFile(content,
    /# helium-linux [^\n]*/,
    `# helium-linux ${heliumLinuxTag}`
  );
}

// Onboarding (URL + hash)
content = replaceInFile(content,
  /(helium-onboarding = fetchurl \{\s*url = ")[^"]*(";\s*hash = ")[^"]*(")/s,
  `$1${onboardingUrl}$2${onboardingHash}$3`
);

// uBlock (URL + hash)
content = replaceInFile(content,
  /(helium-ublock = fetchurl \{\s*url = ")[^"]*(";\s*hash = ")[^"]*(")/s,
  `$1${ublockUrl}$2${ublockHash}$3`
);

// Search engines (URL + hash)
content = replaceInFile(content,
  /(helium-search-engines-data = fetchurl \{\s*url = ")[^"]*(";\s*hash = ")[^"]*(")/s,
  `$1${searchEnginesUrl}$2${searchEnginesHash}$3`
);

writeFileSync(defaultNixPath, content);

// 7. Check info.json
const infoJson = JSON.parse(readFileSync(infoJsonPath, "utf-8"));
const currentChromium = infoJson.chromium?.version;
if (currentChromium !== chromiumVersion) {
  console.log(`\n⚠ Chromium base changed: ${currentChromium} → ${chromiumVersion}`);
  console.log("info.json needs updating. Run the chromium update script:");
  console.log(`  cd chromium && nix-shell -p zx --run 'zx update.mjs --chromium'`);
} else {
  console.log("Chromium base unchanged, info.json is fine.");
}

console.log(`\n✓ Updated to Helium ${newHeliumVersion} (Chromium ${chromiumVersion})`);
