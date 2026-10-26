// Reproducible PCM tones. The incoming cadence is a telephone bell; the caller
// gets the standard two-tone ringback with a long waiting interval.
const fs = require('node:fs');
const path = require('node:path');
const rate = 22050;
function write(name, seconds, sample) {
  const length = Math.floor(seconds * rate);
  const out = Buffer.alloc(44 + length * 2);
  out.write('RIFF'); out.writeUInt32LE(out.length - 8, 4); out.write('WAVEfmt ', 8);
  out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(rate, 24); out.writeUInt32LE(rate * 2, 28);
  out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34);
  out.write('data', 36); out.writeUInt32LE(length * 2, 40);
  for (let i = 0; i < length; i++) out.writeInt16LE(Math.round(sample(i / rate) * 15000), 44 + i * 2);
  fs.writeFileSync(path.join(__dirname, '..', 'assets', 'sounds', name + '.wav'), out);
}
const sine = (f, t) => Math.sin(2 * Math.PI * f * t);
write('ringback', 6, t => t < 2 ? (sine(440, t) + sine(480, t)) * .45 * Math.min(1, t * 100, (2 - t) * 100) : 0);
write('incoming_call', 3, t => {
  const on = t < .8 || (t >= 1 && t < 1.8);
  return on ? (sine(1200, t) + sine(1600, t)) * .4 * (.6 + .4 * sine(25, t)) : 0;
});
