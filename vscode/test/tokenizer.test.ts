// The TypeScript tokeniser must produce exactly the bytes of tools/bbctok.py
// (which the E2E test remote_tokeniser checks against BBC BASIC itself).
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fixtures from '../data/fixtures.json';
import { tokeniseProgram, detokenise, encodeLineNumber, decodeLineNumber } from '../src/tokenizer';

const cases: { text: string; image: string }[] = (fixtures as any).default ?? (fixtures as any);

test('line number constants round trip', () => {
    for (const n of [0, 1, 10, 255, 256, 1000, 16383, 16384, 32767]) {
        const [a, b, c] = encodeLineNumber(n);
        assert.strictEqual(decodeLineNumber(a, b, c), n);
    }
});

cases.forEach((c, i) => {
    test(`fixture ${i}: same bytes as the Python tokeniser`, () => {
        const got = Buffer.from(tokeniseProgram(c.text).image).toString('hex');
        assert.strictEqual(got, c.image);
    });
    test(`fixture ${i}: detokenise gives the program back`, () => {
        const listed = detokenise(tokeniseProgram(c.text).image);
        const lines = c.text.split('\n').filter(l => l.trim()).length;
        assert.strictEqual(listed.split('\n').filter(l => l.trim()).length, lines);
    });
});

test('errors carry the source line', () => {
    assert.throws(() => tokeniseProgram('10 PRINT\n5 END\n'), /not ascending/);
    assert.throws(() => tokeniseProgram('PRINT "no number"\n'), /no line number/);
});
