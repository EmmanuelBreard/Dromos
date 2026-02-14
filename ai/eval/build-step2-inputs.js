// Build step2-inputs.yaml from the latest v4 Step 1 outputs
// Usage: node build-step2-inputs.js

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const RESULTS_DIR = path.join(__dirname, 'results', 'step1-outputs');
const ATHLETES_PATH = path.join(__dirname, 'vars', 'athletes.yaml');
const OUTPUT_PATH = path.join(__dirname, 'vars', 'step2-inputs.yaml');

// Map athlete names to their v4 output files
const V4_FILES = {
  'Alex - Beginner Olympic': 'alex-beginner-olympic-v4.md',
  'Jordan - Experienced Half-Ironman': 'jordan-experienced-half-ironman-v4.md',
  'Sam - Time-Crunched Sprint': 'sam-time-crunched-sprint-v4.md',
};

// Load athletes.yaml for weekly_hours
const athletesRaw = fs.readFileSync(ATHLETES_PATH, 'utf8');
const athletes = yaml.load(athletesRaw);

const entries = [];

for (const athlete of athletes) {
  const name = athlete.vars.athlete_name;
  const file = V4_FILES[name];
  if (!file) {
    console.warn(`No v4 file for ${name}, skipping`);
    continue;
  }

  const md = fs.readFileSync(path.join(RESULTS_DIR, file), 'utf8');

  // Extract raw markdown between ```markdown and ```
  const match = md.match(/```markdown\n([\s\S]*?)```/);
  if (!match) {
    console.warn(`No markdown block found in ${file}, skipping`);
    continue;
  }

  const rawMarkdown = match[1].trimEnd();

  entries.push({
    athlete_name: name,
    weekly_hours: athlete.vars.weekly_hours,
    step1_output: rawMarkdown,
  });

  console.log(`  ${name}: extracted ${rawMarkdown.split('\n').length} lines`);
}

// Write step2-inputs.yaml
let out = '# Auto-generated from v4 step 1 outputs — do not edit\n\n';

for (const e of entries) {
  out += `- vars:\n`;
  out += `    athlete_name: "${e.athlete_name}"\n`;
  out += `    weekly_hours: "${e.weekly_hours}"\n`;
  out += `    step1_output: |\n`;
  for (const line of e.step1_output.split('\n')) {
    out += `      ${line}\n`;
  }
  out += '\n';
}

fs.writeFileSync(OUTPUT_PATH, out);
console.log(`\nWrote ${entries.length} entries to ${OUTPUT_PATH}`);
