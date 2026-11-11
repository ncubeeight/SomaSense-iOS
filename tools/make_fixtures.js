#!/usr/bin/env node
// Writes the parity fixtures the iOS tests check against, by running the prototype's own code.
// Usage: node tools/make_fixtures.js [path to the Android SomaSense repo]
// The Android repo defaults to ~/Desktop/symptom-tracker-android, or set SOMASENSE_ANDROID.
// The body model is taken straight out of design/project/Main.dc.html, so a change there that alters
// where taps land or what they're called makes the Swift tests fail until the port catches up.
const fs = require('fs');
const path = require('path');

const project = path.resolve(__dirname, '..');
const android = process.argv[2] || process.env.SOMASENSE_ANDROID || path.join(require('os').homedir(), 'Desktop/symptom-tracker-android');
const source = fs.readFileSync(path.join(android, 'design/project/Main.dc.html'), 'utf8');
const m = source.match(/\n  bodyModel\(\) \{\n([\s\S]*?)\n  \}\n\n  zonePoint\(id\)/);
if (!m) throw new Error('bodyModel() not found in Main.dc.html');
const BODY = new Function(m[1])();
const mesh = JSON.parse(fs.readFileSync(path.join(project, 'SomaSense/Resources/body-mesh.json'), 'utf8'));
BODY.setMesh(mesh);

const round = (v) => Math.round(v * 1e4) / 1e4;
const taps = [];
for (const yaw of [0, 30, 90, 135, 180, -60, -90]) {
  for (let sy = 4; sy < 440; sy += 6) {
    for (let sx = -114; sx < 120; sx += 6) {
      const r = BODY.cast(sx, sy, yaw);
      if (!r.hit) continue;
      const c = BODY.classify(r.p, r.n, r.tag);
      taps.push({ yaw, sx, sy, p: r.p.map(round), label: c.label, area: c.area });
    }
  }
}
const out = path.join(project, 'SomaSenseTests/Fixtures/taps.json');
fs.writeFileSync(out, JSON.stringify(taps));
console.log(taps.length, 'taps written to', path.relative(project, out));

// The same on reshaped bodies, weighted as applyShape() does.
const shapes = JSON.parse(fs.readFileSync(path.join(project, 'SomaSense/Resources/body-shapes.json'), 'utf8'));
const shaped = [];
for (const b of [{ g: 60, b: -40 }, { g: -80, b: 100 }]) {
  BODY.setOffsets([
    { d: shapes.f, w: Math.max(0, -b.g) / 100 }, { d: shapes.m, w: Math.max(0, b.g) / 100 },
    { d: shapes.s, w: Math.max(0, -b.b) / 100 }, { d: shapes.h, w: Math.max(0, b.b) / 100 * 1.5 }
  ]);
  for (const yaw of [0, 90, 180]) {
    for (let sy = 4; sy < 440; sy += 10) {
      for (let sx = -114; sx < 120; sx += 10) {
        const r = BODY.cast(sx, sy, yaw);
        if (!r.hit) continue;
        const c = BODY.classify(r.p, r.n, r.tag);
        shaped.push({ g: b.g, b: b.b, yaw, sx, sy, p: r.p.map(round), label: c.label, area: c.area });
      }
    }
  }
}
const out2 = path.join(project, 'SomaSenseTests/Fixtures/taps-shaped.json');
fs.writeFileSync(out2, JSON.stringify(shaped));
console.log(shaped.length, 'taps on reshaped bodies written to', path.relative(project, out2));
