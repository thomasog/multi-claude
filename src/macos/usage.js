// usage.js - the last usage Claude itself recorded in a data folder (JavaScript for Automation).
//   osascript -l JavaScript usage.js <data folder>
// Prints "5h 34%, week 12% at 14:10" from the newest sample of plan-usage-history.json, or nothing
// when the file is missing or unknown. It is only as fresh as the last time that Claude was open.
ObjC.import('Foundation');

function pad(n) { return String(n).padStart(2, '0'); }
function day(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }

function note(dataDir) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(`${dataDir}/plan-usage-history.json`, $.NSUTF8StringEncoding, null);
  if (text.isNil()) return '';
  let last;
  try {
    last = JSON.parse(text.js).samples.reduce((a, b) => (b.t > a.t ? b : a));
  } catch (e) {
    return '';
  }
  const usage = (last && last.u) || {};
  const parts = [['fh', '5h'], ['sd', 'week']].filter(([key]) => key in usage).map(([key, label]) => `${label} ${usage[key]}%`);
  if (!parts.length || typeof last.t !== 'number') return '';
  const at = new Date(last.t);
  const time = `${pad(at.getHours())}:${pad(at.getMinutes())}`;
  return `${parts.join(', ')} at ${day(at) === day(new Date()) ? time : `${day(at)} ${time}`}`;
}

function run(argv) {
  return argv.length ? note(argv[0]) : '';
}
