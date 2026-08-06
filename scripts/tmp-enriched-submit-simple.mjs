import fs from 'node:fs';

const formId = '262176902106049';
const auditJson = fs.readFileSync('dist/keeper-audit.json', 'utf8');
const body = new URLSearchParams({
  formID: formId,
  q2_textarea0: auditJson
});

const response = await fetch(`https://submit.jotform.com/submit/${formId}`, {
  method: 'POST',
  headers: { 'content-type': 'application/x-www-form-urlencoded;charset=UTF-8' },
  body,
  redirect: 'follow'
});

const output = { status: response.status, url: response.url };
fs.writeFileSync('dist/enriched-submit-result.json', JSON.stringify(output, null, 2));
console.log(JSON.stringify(output));
