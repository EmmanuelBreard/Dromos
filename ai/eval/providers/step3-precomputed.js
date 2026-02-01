// Custom promptfoo provider that returns pre-computed Step 3 outputs
// from the block orchestrator (run-step3-blocks.js)

const fs = require('fs');
const path = require('path');

const outputsPath = path.join(__dirname, '..', 'results', 'step3-outputs.json');

class Step3PrecomputedProvider {
  constructor(options) {
    this.outputs = [];
    this.callIndex = 0;
    try {
      this.outputs = JSON.parse(fs.readFileSync(outputsPath, 'utf8'));
    } catch (e) {
      // Will return error at eval time
    }
  }

  id() {
    return 'step3-blocks';
  }

  async callApi(prompt) {
    const output = this.outputs[this.callIndex] || '{"error": "No pre-computed output for index ' + this.callIndex + '"}';
    this.callIndex++;
    return { output };
  }
}

module.exports = Step3PrecomputedProvider;
