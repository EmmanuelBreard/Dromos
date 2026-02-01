// Reads step 2 promptfoo results (MD→JSON) and creates step 3 input vars
// Each step 2 output (JSON macro plan) becomes a test case for workout selection

const fs = require('fs');
const path = require('path');

const step2ResultsPath = path.join(__dirname, 'results', 'step2.json');
const step1ResultsPath = path.join(__dirname, 'results', 'step1.json');
const outputPath = path.join(__dirname, 'vars', 'step3-inputs.yaml');

if (!fs.existsSync(step2ResultsPath)) {
  console.error('No step 2 results found. Run step 2 first.');
  process.exit(1);
}

const step2Data = JSON.parse(fs.readFileSync(step2ResultsPath, 'utf8'));
const step2Results = step2Data.results?.results || step2Data.results || [];

// Load step 1 results to carry forward athlete vars (name, limiters, constraints)
let step1Results = [];
if (fs.existsSync(step1ResultsPath)) {
  const step1Data = JSON.parse(fs.readFileSync(step1ResultsPath, 'utf8'));
  step1Results = step1Data.results?.results || step1Data.results || [];
}

let yaml = '# Auto-generated from step 2 outputs — do not edit\n\n';
let count = 0;

for (let i = 0; i < step2Results.length; i++) {
  const r = step2Results[i];
  const rawOutput = r.response?.output || r.output || '';

  if (!rawOutput || rawOutput.includes('Error')) {
    console.warn(`Skipping step 2 result ${i}: no valid output`);
    continue;
  }

  // Clean and validate it's parseable JSON
  const cleaned = rawOutput.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
  try {
    JSON.parse(cleaned);
  } catch (e) {
    console.warn(`Skipping step 2 result ${i}: invalid JSON — ${e.message}`);
    continue;
  }

  // Carry forward athlete vars from step 1 (matched by index)
  // Step 2 inputs were generated from step 1, so indices align
  const step1Vars = step1Results[i]?.vars || {};
  const athleteName = r.vars?.athlete_name || step1Vars.athlete_name || `athlete_${i + 1}`;
  const limiters = step1Vars.limiters || 'none specified';
  const constraints = step1Vars.constraints || 'none';

  yaml += `- vars:\n`;
  yaml += `    athlete_name: "${athleteName}"\n`;
  yaml += `    limiters: "${limiters}"\n`;
  yaml += `    constraints: "${constraints}"\n`;
  yaml += `    macro_plan_json: |\n`;

  // Indent each line for YAML block scalar
  const lines = cleaned.split('\n');
  for (const line of lines) {
    yaml += `      ${line}\n`;
  }
  yaml += '\n';
  count++;
}

if (count === 0) {
  console.error('No valid step 2 outputs to extract. Check step 2 results.');
  process.exit(1);
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, yaml);
console.log(`Wrote ${count} test cases to ${outputPath}`);
