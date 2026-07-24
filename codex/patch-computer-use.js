#!/usr/bin/env node
"use strict";

// This file only adapts upstream patch discovery to the current hashed bundle
// name. Computer Use behavior remains sourced from codex-desktop-linux.

const fs = require("node:fs");
const path = require("node:path");

const linuxPortRoot = path.resolve(process.argv[2] ?? "");
const extractedApp = path.resolve(process.argv[3] ?? "");
if (!fs.existsSync(linuxPortRoot) || !fs.existsSync(extractedApp)) {
  console.error("usage: patch-computer-use.js LINUX_PORT_ROOT EXTRACTED_APP");
  process.exit(2);
}

process.env.CODEX_LINUX_ENABLE_COMPUTER_USE_UI = "1";

const { patchExtractedApp } = require(
  path.join(linuxPortRoot, "scripts/patches/runner.js"),
);
const implementation = require(
  path.join(linuxPortRoot, "scripts/patches/impl/computer-use.js"),
);
const coreRoot = path.join(
  linuxPortRoot,
  "scripts/patches/core/all-linux",
);

patchExtractedApp(extractedApp, {
  corePatchRoot: path.join(coreRoot, "main-process/computer-use"),
});
patchExtractedApp(extractedApp, {
  corePatchRoot: path.join(coreRoot, "webview/computer-use-ui"),
});

const assetsDirectory = path.join(extractedApp, "webview/assets");
const javaScriptAssets = fs.readdirSync(assetsDirectory)
  .filter((name) => name.endsWith(".js"))
  .map((name) => path.join(assetsDirectory, name));

function applyToUniqueAsset(label, patchFunction, alreadyPatched, isCandidate) {
  const changed = [];
  const existing = [];
  for (const target of javaScriptAssets) {
    const source = fs.readFileSync(target, "utf8");
    if (alreadyPatched(source)) {
      existing.push(target);
      continue;
    }
    if (!isCandidate(source)) {
      continue;
    }
    const patched = patchFunction(source);
    if (patched !== source) {
      changed.push({ target, patched });
    }
  }
  if (existing.length === 1 && changed.length === 0) {
    return;
  }
  if (existing.length !== 0 || changed.length !== 1) {
    throw new Error(
      `${label}: expected one target, found existing=${existing.length}, changed=${changed.length}`,
    );
  }
  fs.writeFileSync(changed[0].target, changed[0].patched, "utf8");
  console.log(`${label}: ${path.basename(changed[0].target)}`);
}

applyToUniqueAsset(
  "Linux Computer Use host platform",
  implementation.applyLinuxComputerUseHostPlatformPatch,
  (source) =>
    /featureName:`computer_use`[\s\S]{0,2200}?isHostCompatiblePlatform:[A-Za-z_$][\w$]*===`linux`\|\|/.test(
      source,
    ),
  (source) => source.includes("featureName:`computer_use`"),
);
applyToUniqueAsset(
  "Linux Computer Use install flow",
  implementation.applyLinuxComputerUseInstallFlowPatch,
  (source) =>
    source.includes("plugin detail query requires pluginName") &&
    /let [A-Za-z_$][\w$]*=[A-Za-z_$][\w$]*&&[A-Za-z_$][\w$]*!==`computer-use`,/.test(
      source,
    ),
  (source) => source.includes("plugin detail query requires pluginName"),
);

const iconCandidates = fs.readdirSync(assetsDirectory)
  .filter((name) => /^computer-use-plugin-icon-[^.]+\.png$/.test(name))
  .filter((name) => name !== "computer-use-plugin-icon-linux.png");
if (iconCandidates.length !== 1) {
  throw new Error(
    `Computer Use icon: expected one source, found ${iconCandidates.length}`,
  );
}
let iconReferences = 0;
for (const target of javaScriptAssets) {
  const source = fs.readFileSync(target, "utf8");
  if (!source.includes("computer-use-plugin-icon-linux.png")) {
    continue;
  }
  fs.writeFileSync(
    target,
    source.replaceAll(
      "computer-use-plugin-icon-linux.png",
      iconCandidates[0],
    ),
    "utf8",
  );
  iconReferences += 1;
}
if (iconReferences !== 1) {
  throw new Error(
    `Computer Use icon: expected one patched reference, found ${iconReferences}`,
  );
}

const mainBundle = fs.readdirSync(path.join(extractedApp, ".vite/build"))
  .filter((name) => /^main-[^.]+\.js$/.test(name));
if (mainBundle.length !== 1) {
  throw new Error(`main bundle: expected one target, found ${mainBundle.length}`);
}
const mainSource = fs.readFileSync(
  path.join(extractedApp, ".vite/build", mainBundle[0]),
  "utf8",
);
for (const marker of [
  "codexLinuxNativeDesktopApps(",
  "codexLinuxRegisterComputerUseCursorHandler",
  "platform!==`darwin`&&",
]) {
  if (!mainSource.includes(marker)) {
    throw new Error(`main bundle: missing upstream marker ${marker}`);
  }
}
console.log("Linux Computer Use upstream patches applied");
