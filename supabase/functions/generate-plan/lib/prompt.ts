/**
 * Replace every `{{key}}` in a prompt.
 *
 * `String.prototype.replace` only changes the first match, and a string
 * replacement interprets `$`` / `$'` / `$&`. The step 1 prompt repeats
 * `{{total_weeks}}` and `{{weekly_hours}}`; leaving the later copies literal
 * makes the model ignore the short-plan and volume rules. A function
 * replacement inserts the value exactly.
 */
export function fillTemplate(
  template: string,
  vars: Record<string, string>,
): string {
  return template.replace(/\{\{([a-z0-9_]+)\}\}/gi, (match, key: string) => {
    if (!Object.prototype.hasOwnProperty.call(vars, key)) return match;
    return vars[key];
  });
}
