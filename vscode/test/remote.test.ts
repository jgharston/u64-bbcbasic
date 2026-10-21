// Output streaming (src/remote.ts): text passed on while BASIC prints must
// add up to the finished output, wherever the ring reads split it.
import { test } from 'node:test';
import * as assert from 'node:assert';
import { cleanOutput, completeLines } from '../src/remote';

const bytes = (s: string) => Array.from(Buffer.from(s, 'latin1'));

// runLines' emit: whole lines while running, everything at the end
function stream(chunks: number[][]): string {
    const raw: number[] = [];
    let shown = '', got = '';
    const emit = (final: boolean) => {
        const text = cleanOutput(final ? raw : raw.slice(0, completeLines(raw)));
        if (text.length > shown.length) { got += text.slice(shown.length); shown = text; }
    };
    for (const c of chunks) { raw.push(...c); emit(false); }
    emit(true);
    return got;
}

test('a line split by a ring read is passed on whole', () => {
    const line = '         1 squared is          1\r\n';
    const all = bytes(line + '         2 squared is          4\r\n');
    for (let cut = 1; cut < all.length; cut++) {
        assert.strictEqual(stream([all.slice(0, cut), all.slice(cut)]), cleanOutput(all), `cut ${cut}`);
    }
});

test('a CR that is a VDU parameter does not end a line', () => {
    // VDU 31,13,5 (TAB(13,5)) then text
    const raw = [31, 13, 5, ...bytes('AB')];
    assert.strictEqual(completeLines(raw), 0);
    assert.strictEqual(completeLines([...raw, 13, 10]), 6);
});
