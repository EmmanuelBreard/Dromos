// Reads step 1 promptfoo results and creates step 2 input vars
// Maps each step 1 output into a test case for the MD→JSON converter

const fs = require('fs');
const path = require('path');

const resultsPath = path.join(__dirname, 'results', 'step1.json');
const outputPath = path.join(__dirname, 'vars', 'step2-inputs.yaml');

if (!fs.existsSync(resultsPath)) {
  console.error('No step 1 results found. Run step 1 first.');
  process.exit(1);
}

const data = JSON.parse(fs.readFileSync(resultsPath, 'utf8'));
const results = data.results?.results || data.results || [];

let yaml = '# Auto-generated from step 1 outputs — do not edit\n\n';

for (let i = 0; i < results.length; i++) {
  const r = results[i];
  const output = r.response?.output || r.output || '';
  const athleteName = r.vars?.athlete_name || `athlete_${i + 1}`;
  const weeklyHours = r.vars?.weekly_hours || '10';

  if (!output || output.includes('Error')) {
    console.warn(`Skipping result ${i} (${athleteName}): no valid output`);
    continue;
  }

  // Escape the MD output for YAML (use block scalar)
  yaml += `- vars:\n`;
  yaml += `    athlete_name: "${athleteName}"\n`;
  yaml += `    weekly_hours: "${weeklyHours}"\n`;
  yaml += `    step1_output: |\n`;

  // Indent each line for YAML block scalar
  const lines = output.split('\n');
  for (const line of lines) {
    yaml += `      ${line}\n`;
  }
  yaml += '\n';
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, yaml);
console.log(`Wrote ${results.length} test cases to ${outputPath}`);
