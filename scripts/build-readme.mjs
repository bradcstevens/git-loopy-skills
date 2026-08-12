#!/usr/bin/env node
// Regenerates the skill index in README.md between the skills markers.
// Run with --check to fail instead of writing (used by CI).

import { readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const START = "<!-- skills:start -->";
const END = "<!-- skills:end -->";

function readSkill(name) {
  const file = join(repo, "skills", name, "SKILL.md");
  if (!existsSync(file)) return null;
  const frontmatter = readFileSync(file, "utf8").match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!frontmatter) throw new Error(`${name}: SKILL.md has no YAML frontmatter`);
  const body = frontmatter[1];
  const field = (key) => (body.match(new RegExp(`^${key}:\\s*(.*)$`, "m")) || [])[1]?.trim();
  const description = (field("description") || "").replace(/^["']|["']$/g, "");
  if (!field("name")) throw new Error(`${name}: SKILL.md frontmatter is missing 'name'`);
  if (!description) throw new Error(`${name}: SKILL.md frontmatter is missing 'description'`);
  return {
    name,
    description,
    userInvoked: /^disable-model-invocation:\s*true\s*$/m.test(body),
    docs: existsSync(join(repo, "docs", `${name}.md`)) ? `docs/${name}.md` : null,
  };
}

// The description doubles as the agent's trigger text, so it can run long.
// The index only needs the lead sentence.
function summarise(description) {
  const stop = description.search(/\.\s|\. *$/);
  const lead = stop === -1 ? description : description.slice(0, stop + 1);
  return lead.replace(/\|/g, "\\|").trim();
}

// A git-ignored skill directory is local-only: it lives in a working copy but is
// not part of this repo, so it must stay out of the published index.
function ignoredSkills(names) {
  if (names.length === 0) return new Set();
  const result = spawnSync("git", ["check-ignore", "--stdin"], {
    cwd: repo,
    input: names.map((name) => `skills/${name}/\n`).join(""),
    encoding: "utf8",
  });
  // Exit 0 means some paths are ignored, 1 means none are. Anything else (git
  // missing, not a repo) is not a signal, so fall back to indexing everything.
  if (result.error || (result.status !== 0 && result.status !== 1)) return new Set();
  const ignored = result.stdout
    .split("\n")
    .filter(Boolean)
    .map((line) => line.replace(/^skills\//, "").replace(/\/$/, ""));
  return new Set(ignored);
}

const skillDirs = readdirSync(join(repo, "skills"), { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name);

const localOnly = ignoredSkills(skillDirs);

const skills = skillDirs
  .filter((name) => !localOnly.has(name))
  .map((name) => readSkill(name))
  .filter(Boolean)
  .sort((a, b) => a.name.localeCompare(b.name));

const rows = skills.map((skill) => {
  const link = skill.docs ? `[${skill.name}](${skill.docs})` : skill.name;
  const invoke = skill.userInvoked ? `\`/${skill.name}\`` : "automatic";
  return `| ${link} | ${invoke} | ${summarise(skill.description)} |`;
});

const table = [
  "| Skill | Invoke | What it does |",
  "| --- | --- | --- |",
  ...rows,
].join("\n");

const readmePath = join(repo, "README.md");
const readme = readFileSync(readmePath, "utf8");
const startIndex = readme.indexOf(START);
const endIndex = readme.indexOf(END);
if (startIndex === -1 || endIndex === -1) {
  throw new Error(`README.md is missing the ${START} / ${END} markers`);
}

const updated =
  readme.slice(0, startIndex + START.length) + "\n\n" + table + "\n\n" + readme.slice(endIndex);

if (process.argv.includes("--check")) {
  if (updated !== readme) {
    console.error("README.md skill index is out of date. Run: node scripts/build-readme.mjs");
    process.exit(1);
  }
  console.log(`README.md skill index is up to date (${skills.length} skills).`);
} else {
  writeFileSync(readmePath, updated);
  console.log(`Wrote skill index to README.md (${skills.length} skills).`);
}
