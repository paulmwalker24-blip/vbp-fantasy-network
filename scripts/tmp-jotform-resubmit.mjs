import fs from 'node:fs';

const formId = '262176902106049';
const auditJson = fs.readFileSync('dist/keeper-audit.json', 'utf8');
const formUrl = `https://form.jotform.com/${formId}`;

const formResponse = await fetch(formUrl);
if (!formResponse.ok) throw new Error(`Could not load Jotform form: HTTP ${formResponse.status}`);
const html = await formResponse.text();

const actionMatch = html.match(/<form[^>]+action=["']([^"']+)["']/i);
const action = actionMatch?.[1] || `https://submit.jotform.com/submit/${formId}`;

const params = new URLSearchParams();
for (const tag of html.matchAll(/<input\b[^>]*>/gi)) {
  const source = tag[0];
  const name = source.match(/\bname=["']([^"']+)["']/i)?.[1];
  if (!name) continue;
  const value = source.match(/\bvalue=["']([^"']*)["']/i)?.[1] || '';
  params.set(name, value);
}

let fieldName = null;
for (const tag of html.matchAll(/<textarea\b[^>]*>/gi)) {
  const source = tag[0];
  const name = source.match(/\bname=["']([^"']+)["']/i)?.[1];
  const id = source.match(/\bid=["']([^"']+)["']/i)?.[1];
  if (name && (id === 'input_2' || name.startsWith('q2_'))) {
    fieldName = name;
    break;
  }
}

if (!fieldName) {
  const candidate = html.match(/\bname=["'](q2_[^"']+)["']/i);
  fieldName = candidate?.[1] || 'q2_input2';
}

params.set('formID', formId);
params.set(fieldName, auditJson);
params.set('q2_input2', auditJson);
params.set('q2_textarea0', auditJson);

const submission = await fetch(action, {
  method: 'POST',
  headers: { 'content-type': 'application/x-www-form-urlencoded;charset=UTF-8' },
  body: params,
  redirect: 'follow'
});

const output = {
  formStatus: formResponse.status,
  action,
  fieldName,
  submissionStatus: submission.status,
  submissionUrl: submission.url
};

fs.writeFileSync('dist/jotform-submit-result.json', JSON.stringify(output, null, 2));
console.log(JSON.stringify(output));
