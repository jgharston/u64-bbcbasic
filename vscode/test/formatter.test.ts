// The formatter (src/formatter.ts) and the indentation stripping on upload.
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { formatProgram, stripIndent } from '../src/formatter';
import { tokeniseProgram } from '../src/tokenizer';

test('blocks indent by 2 per level; a closing line goes back first', () => {
    const src = ['10 DEF PROCa', '20 LOCAL I%', '30 FOR I%=1 TO 3', '40 REPEAT',
                 '50 A%=A%+1', '60 UNTIL A%>9', '70 NEXT', '80 ENDPROC'].join('\n');
    assert.strictEqual(formatProgram(src), ['10 DEF PROCa', '20   LOCAL I%',
        '30   FOR I%=1 TO 3', '40     REPEAT', '50       A%=A%+1', '60     UNTIL A%>9',
        '70   NEXT', '80 ENDPROC'].join('\n'));
});

test('one-line loops, IF ... ENDPROC, single-line FN, REM and strings', () => {
    const src = ['10 DEF PROCb', '20 FOR I%=1 TO 3:PRINT I%:NEXT', '30 IF A% THEN ENDPROC',
                 '40 PRINT "FOR:NEXT"', '50 REM REPEAT', '60 ENDPROC', '70 DEF FNsq(X)=X*X',
                 '80 PRINT FNsq(2)'].join('\n');
    assert.strictEqual(formatProgram(src), ['10 DEF PROCb', '20   FOR I%=1 TO 3:PRINT I%:NEXT',
        '30   IF A% THEN ENDPROC', '40   PRINT "FOR:NEXT"', '50   REM REPEAT', '60 ENDPROC',
        '70 DEF FNsq(X)=X*X', '80 PRINT FNsq(2)'].join('\n'));
});

test('a multi-line FN ends at its = line; REPEAT inside a line', () => {
    const src = ['10 DEF FNf(A%)', '20 LOCAL B%', '30 B%=0:REPEAT B%=B%+1', '40 UNTIL B%>A%',
                 '50 =B%'].join('\n');
    assert.strictEqual(formatProgram(src), ['10 DEF FNf(A%)', '20   LOCAL B%',
        '30   B%=0:REPEAT B%=B%+1', '40   UNTIL B%>A%', '50 =B%'].join('\n'));
});

test('REPEAT followed by a statement without a colon', () => {
    const src = ['10 DEF PROCw', '20 T%=TIME:REPEAT UNTIL TIME>T%', '30 REPEAT A%=A%+1:UNTIL A%>3',
                 '40 ENDPROC'].join('\n');
    assert.strictEqual(formatProgram(src), ['10 DEF PROCw', '20   T%=TIME:REPEAT UNTIL TIME>T%',
        '30   REPEAT A%=A%+1:UNTIL A%>3', '40 ENDPROC'].join('\n'));
});

test('formatting is idempotent and keeps CRLF', () => {
    const src = '10 FOR I%=1 TO 2\r\n20 PRINT I%\r\n30 NEXT\r\n';
    const once = formatProgram(src);
    assert.strictEqual(once, '10 FOR I%=1 TO 2\r\n20   PRINT I%\r\n30 NEXT\r\n');
    assert.strictEqual(formatProgram(once), once);
});

test('the demo sources are formatted as written (not the classics)', () => {
    const root = path.join(__dirname, '..', '..', '..', 'demos');
    const files: string[] = [];
    for (const d of fs.readdirSync(root)) {
        if (d === 'classics') { continue; }
        const dir = path.join(root, d);
        if (!fs.statSync(dir).isDirectory()) { continue; }
        for (const f of fs.readdirSync(dir)) {
            if (f.toLowerCase().endsWith('.bas')) { files.push(path.join(dir, f)); }
        }
    }
    assert.ok(files.length > 30, `${files.length} demo files`);
    for (const f of files) {
        const text = fs.readFileSync(f, 'latin1');
        assert.strictEqual(formatProgram(text), text, path.relative(root, f));
    }
});

test('upload drops the indentation; keepIndent keeps it', () => {
    assert.strictEqual(stripIndent('120     PRINT'), '120 PRINT');
    const indented = '10 FOR I%=1 TO 2\n20   PRINT I%\n30 NEXT\n';
    const flat = '10 FOR I%=1 TO 2\n20 PRINT I%\n30 NEXT\n';
    assert.deepStrictEqual(tokeniseProgram(indented).image, tokeniseProgram(flat).image);
    assert.ok(tokeniseProgram(indented, true).image.length > tokeniseProgram(flat).image.length);
});
