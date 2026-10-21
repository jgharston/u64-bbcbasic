// Remote control of U64 BBC BASIC through the MOS mailbox.
//
// TypeScript port of tools/u64remote.py (protocol: docs/REMOTE_DEV.md),
// talking to the Ultimate's REST API with Node's http module. No VS Code
// dependency, so it can be tested from Node against a real machine.

import * as http from 'http';
import { tokeniseProgram, detokenise } from './tokenizer';

// Mailbox layout (src/mos/defs.s)
export const MBOX = 0xc6e0;
const MB = {
    HSEQ: 5, CSEQ: 6, REQ: 7, STATUS: 8, LINENO: 9, DEBUG: 11, RINGW: 12, RINGR: 13,
    CAPTURE: 14, LINELEN: 15, PROMPT: 17, ERRNUM: 18, ERRCNT: 19, LINE: 20,
    BREAK: 94, RING: 110,
};
const MB_SIZE = 238, MB_LINEMAX = 74, RING = 128;
const REQ_LINE = 1, REQ_DEBUG = 2, REQ_CAPTURE = 3, REQ_PROGRAM = 4;
export const DBG_CONTINUE = 1, DBG_STEP = 2, DBG_STOP = 3;
const PAGE = 0x1d00, HIMEM = 0x8000, ESCFLG = 0x00ff, SCREEN = 0xc000;

export type State = 'prompt' | 'input' | 'running' | 'paused' | 'idle' | 'timeout';

export interface MachineState {
    state: State; errorCount: number; lastError: number; capture: boolean; line: number;
}

export interface BasicError { number: number; message: string; line: number | null; }

export interface RunResult {
    ok: boolean; state: State; output: string; error: BasicError | null;
    elapsed: number; programBytes?: number; line?: number;
}

export class RemoteError extends Error {}

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

export class Remote {
    constructor(public host: string, private password?: string, private requestTimeout = 10000) {}

    // --- REST ---------------------------------------------------------------

    private request(method: string, path: string, body?: Uint8Array): Promise<Buffer> {
        return new Promise((resolve, reject) => {
            const headers: Record<string, string> = {};
            if (body) { headers['Content-Type'] = 'application/octet-stream'; }
            if (this.password) { headers['X-Password'] = this.password; }
            const req = http.request({ host: this.host, port: 80, method, path, headers,
                                       timeout: this.requestTimeout }, res => {
                const chunks: Buffer[] = [];
                res.on('data', c => chunks.push(c));
                res.on('end', () => (res.statusCode ?? 500) >= 400
                    ? reject(new RemoteError(`${method} ${path}: HTTP ${res.statusCode}`))
                    : resolve(Buffer.concat(chunks)));
            });
            req.on('timeout', () => req.destroy(new RemoteError(`${this.host}: time-out`)));
            req.on('error', e => reject(e instanceof RemoteError ? e : new RemoteError(`${this.host}: ${e.message}`)));
            if (body) { req.write(body); }
            req.end();
        });
    }

    /** Retried: the firmware refuses DMA while a UCI transfer runs. */
    private async retry<T>(f: () => Promise<T>): Promise<T> {
        for (let attempt = 0; ; attempt++) {
            try { return await f(); } catch (e) {
                if (attempt >= 5) { throw e; }
                await sleep(200);
            }
        }
    }

    async read(address: number, length: number): Promise<Buffer> {
        const hex = address.toString(16).toUpperCase().padStart(4, '0');
        const data = await this.retry(() =>
            this.request('GET', `/v1/machine:readmem?address=${hex}&length=${length}`));
        if (data.length < length) { throw new RemoteError(`short read at $${hex}`); }
        return data.subarray(0, length);
    }

    async write(address: number, data: Uint8Array | number[]): Promise<void> {
        const hex = address.toString(16).toUpperCase().padStart(4, '0');
        await this.retry(() => this.request('POST', `/v1/machine:writemem?address=${hex}`,
                                            Uint8Array.from(data)));
    }

    async info(): Promise<any> {
        return JSON.parse((await this.request('GET', '/v1/info')).toString());
    }

    // --- mailbox --------------------------------------------------------------

    /** The mailbox header (20 bytes). Every REST read is a DMA that stops
     *  the C64's CPU; long reads during serial-bus transfers (*STATUS, *CP)
     *  break their timing, so polls stay short (see u64remote.py). */
    async mailbox(): Promise<Buffer> {
        const mb = await this.read(MBOX, MB.LINE);
        if (mb.subarray(0, 4).toString('latin1') !== 'BBCR') {
            throw new RemoteError(`U64 BBC BASIC is not running on ${this.host}`);
        }
        return mb;
    }

    stateOf(mb: Buffer): MachineState {
        const waiting = mb[MB.STATUS] === 1;
        return {
            state: waiting ? (mb[MB.PROMPT] === 0x07 ? 'prompt' : 'input')
                           : (mb[MB.STATUS] === 2 ? 'running' : mb[MB.STATUS] === 3 ? 'paused' : 'idle'),
            errorCount: mb[MB.ERRCNT], lastError: mb[MB.ERRNUM], capture: mb[MB.CAPTURE] !== 0,
            line: mb[MB.LINENO] | (mb[MB.LINENO + 1] << 8),
        };
    }

    async state(): Promise<MachineState> { return this.stateOf(await this.mailbox()); }

    async post(request: number, data: Uint8Array | number[] = [], timeout = 10000): Promise<void> {
        if (data.length > MB_LINEMAX) { throw new RemoteError(`line longer than ${MB_LINEMAX} characters`); }
        const mb = await this.mailbox();
        const seq = (mb[MB.HSEQ] + 1) & 0xff;
        if (data.length) { await this.write(MBOX + MB.LINE, Array.from(data)); }
        await this.write(MBOX + MB.LINELEN, [data.length]);
        await this.write(MBOX + MB.REQ, [request]);
        await this.write(MBOX + MB.HSEQ, [seq]);           // last: makes it valid
        const deadline = Date.now() + timeout;
        while ((await this.read(MBOX + MB.CSEQ, 1))[0] !== seq) {
            if (Date.now() > deadline) { throw new RemoteError('the MOS did not take the request'); }
            await sleep(50);
        }
    }

    /** Get BASIC to its prompt: a paused debug session is stopped, a
     *  running program gets ESCAPE, debug mode goes off. */
    async ensurePrompt(): Promise<MachineState> {
        let st = await this.state();
        if (st.state === 'paused') { await this.post(REQ_DEBUG, [DBG_STOP]); }
        else if (st.state === 'running') { await this.stop(); }
        await this.write(MBOX + MB.DEBUG, [0]);
        st = await this.waitLineWanted(10000);
        if (st.state !== 'prompt') { throw new RemoteError('BASIC is waiting for INPUT, not at the prompt'); }
        return st;
    }

    async waitLineWanted(timeout: number): Promise<MachineState> {
        const deadline = Date.now() + timeout;
        for (;;) {
            const st = await this.state();
            if (st.state === 'prompt' || st.state === 'input') { return st; }
            if (Date.now() > deadline) { throw new RemoteError(`BASIC is busy (${st.state})`); }
            await sleep(100);
        }
    }

    async drain(mb?: Buffer): Promise<number[]> {
        mb = mb ?? await this.mailbox();
        const w = mb[MB.RINGW], r = mb[MB.RINGR];
        if (w === r) { return []; }
        let out: number[];                  // only the new part of the ring
        if (w > r) {
            out = Array.from(await this.read(MBOX + MB.RING + r, w - r));
        } else {
            out = Array.from(await this.read(MBOX + MB.RING + r, RING - r));
            if (w) { out = out.concat(Array.from(await this.read(MBOX + MB.RING, w))); }
        }
        await this.write(MBOX + MB.RINGR, [w]);
        return out;
    }

    // --- operations -----------------------------------------------------------

    /** Type lines at the prompt or INPUT; collect output and errors.
     *  onOutput receives output text as it arrives. */
    async runLines(lines: string[], timeout = 30000, onOutput?: (text: string) => void,
                   prepared?: { errorsBefore: number }): Promise<RunResult> {
        let errorsBefore: number;
        if (prepared) {
            errorsBefore = prepared.errorsBefore;
        } else {
            const st = await this.waitLineWanted(10000);
            errorsBefore = st.errorCount;
            await this.post(REQ_CAPTURE, [1]);
            await this.drain();
        }
        const raw: number[] = [];
        const start = Date.now(), deadline = start + timeout;
        const pending = [...lines];
        let state: State = 'running';
        let shown = '';
        const emit = () => {
            if (!onOutput) { return; }
            const text = cleanOutput(raw);
            if (text.length > shown.length) { onOutput(text.slice(shown.length)); shown = text; }
        };
        for (;;) {
            const mb = await this.mailbox();
            raw.push(...await this.drain(mb));
            emit();
            const st = this.stateOf(mb);
            if (st.state === 'paused' && !pending.length) {
                raw.push(...await this.drain());
                emit();
                state = 'paused';
                break;
            }
            if (st.state === 'prompt' || st.state === 'input') {
                if (pending.length) {
                    await this.post(REQ_LINE, latin1(pending.shift()!));
                    continue;
                }
                await sleep(50);
                raw.push(...await this.drain());
                emit();
                state = st.state;
                break;
            }
            if (Date.now() > deadline) { state = 'timeout'; break; }
            await sleep(30);
        }
        const st = await this.state();
        const output = cleanOutput(raw);
        const result: RunResult = { ok: state !== 'timeout', state, output, error: null,
                                    elapsed: (Date.now() - start) / 1000 };
        if (state === 'paused') { result.line = st.line; }
        if (st.errorCount !== errorsBefore) {
            const message = lastLine(output);
            const m = /^(.*) at line (\d+)$/.exec(message);
            result.ok = false;
            result.error = { number: st.lastError, message: m ? m[1] : message,
                             line: m ? Number(m[2]) : null };
        }
        return result;
    }

    async sendProgram(text: string, run: boolean, timeout = 30000,
                      onOutput?: (text: string) => void, keepIndent = false): Promise<RunResult> {
        const { image } = tokeniseProgram(text, keepIndent);
        const [page, himem] = await this.pageHimem();
        if (page + image.length > himem - 1024) {
            throw new RemoteError(`program too big (${image.length} bytes)`);
        }
        const st = await this.ensurePrompt();
        await this.post(REQ_CAPTURE, [1]);
        await this.drain();
        await this.write(page, image);
        await this.post(REQ_PROGRAM, [run ? 1 : 0]);
        const r = await this.runLines([], timeout, onOutput, { errorsBefore: st.errorCount });
        r.programBytes = image.length;
        // capture off when BASIC is back at the prompt (only then does the
        // MOS take requests): nobody reads the ring any more, and a program
        // started later with RUN would wait for the host on a full ring,
        // 2.5-5 s, before the MOS gives up on it
        if (r.state === 'prompt') { await this.post(REQ_CAPTURE, [0]); }
        return r;
    }

    async stop(): Promise<void> { await this.write(ESCFLG, [0x80]); }

    // --- debugger (TRACE hook, docs/REMOTE_DEV.md) -----------------------------

    async setBreakpoints(lines: number[]): Promise<void> {
        const words = [...lines.slice(0, 8), 0, 0, 0, 0, 0, 0, 0, 0].slice(0, 8);
        await this.write(MBOX + MB.BREAK, words.flatMap(n => [n & 0xff, n >> 8]));
    }

    async debugStart(text: string, breakpoints: number[], stopOnEntry: boolean,
                     timeout = 30000, onOutput?: (t: string) => void): Promise<RunResult> {
        const r = await this.sendProgram(text, false, 10000);
        if (r.error) { return r; }
        await this.setBreakpoints(breakpoints);
        await this.write(MBOX + MB.DEBUG, [1 | (stopOnEntry ? 2 : 0)]);
        return this.runLines(['TRACE ON:RUN'], timeout, onOutput);
    }

    async debugResume(how: number, timeout = 30000, onOutput?: (t: string) => void): Promise<RunResult> {
        const st = await this.state();
        if (st.state !== 'paused') { throw new RemoteError(`not paused (${st.state})`); }
        await this.post(REQ_DEBUG, [how]);
        return this.runLines([], timeout, onOutput, { errorsBefore: st.errorCount });
    }

    /** Pause a running program at its next traced line. */
    async requestPause(): Promise<void> {
        const flags = (await this.read(MBOX + MB.DEBUG, 1))[0];
        await this.write(MBOX + MB.DEBUG, [flags | 2]);
    }

    /** Debug mode off; at the prompt also TRACE OFF (RUN keeps TRACE). */
    async debugEnd(): Promise<void> {
        await this.write(MBOX + MB.DEBUG, [0]);
        if ((await this.state()).state === 'prompt') { await this.runLines(['TRACE OFF'], 5000); }
    }

    /** BASIC's variables, decoded from memory (as tools/u64remote.py). */
    async variables(): Promise<Map<string, number | string>> {
        const ws = await this.read(0x0400, 0x100);
        const out = new Map<string, number | string>();
        '@ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('').forEach((name, i) => {
            const v = ws.readInt32LE(i * 4);
            if (v || name === '@') { out.set(name + '%', v); }
        });
        const zp = await this.read(0, 0x52);
        const lomem = zp[0x50] | (zp[0x51] << 8), fsa = zp[0x02] | (zp[0x03] << 8);
        if (!(lomem >= 0x0800 && lomem <= fsa && fsa <= 0x8000)) { return out; }
        const heap = fsa > lomem ? await this.read(lomem, fsa - lomem) : Buffer.alloc(0);
        const rd = async (addr: number, n: number) =>
            addr >= lomem && addr + n <= fsa ? heap.subarray(addr - lomem, addr - lomem + n)
                                             : await this.read(addr, n);
        for (let c = 0x40; c < 0x80; c++) {
            if (c === 0x7b || c === 0x7c) { continue; }        // PROC and FN lists
            let ptr = ws[(2 * c) & 0xff] | (ws[((2 * c) & 0xff) + 1] << 8);
            for (let seen = 0; (ptr >> 8) && seen < 500; seen++) {   // zero high byte ends
                const rec = await rd(ptr, 48);
                let j = 2;
                while (j < rec.length && rec[j] !== 0) { j++; }
                const name = String.fromCharCode(c) + rec.subarray(2, j).toString('latin1');
                const at = ptr + j + 1;
                if (name.endsWith('(')) { out.set(name + ')', 'array'); }
                else if (name.endsWith('%')) { out.set(name, (await rd(at, 4)).readInt32LE(0)); }
                else if (name.endsWith('$')) {
                    const d = await rd(at, 4);
                    const len = d[3];
                    out.set(name, len ? (await rd(d[0] | (d[1] << 8), len)).toString('latin1') : '');
                } else { out.set(name, bbcFloat(await rd(at, 5))); }
                ptr = rec[0] | (rec[1] << 8);
            }
        }
        return out;
    }

    async screen(): Promise<string[]> {
        const data = await this.read(SCREEN, 1000);
        const rows: string[] = [];
        for (let r = 0; r < 25; r++) {
            rows.push(Array.from(data.subarray(r * 40, r * 40 + 40), c => screenChar(c)).join('').replace(/\s+$/, ''));
        }
        return rows;
    }

    /** BASIC's PAGE and HIMEM (zero page &18, &06/&07); the defaults if unset. */
    async pageHimem(): Promise<[number, number]> {
        const zp = await this.read(0, 0x19);
        const page = zp[0x18] << 8, himem = zp[0x06] | (zp[0x07] << 8);
        return page >= 0x0800 && page < himem && himem <= 0x8000 ? [page, himem] : [PAGE, HIMEM];
    }

    async programText(): Promise<string> {
        const parts: Buffer[] = [];
        const [page] = await this.pageHimem();
        for (let i = 0; i < 0x4000; i += 0x1000) { parts.push(await this.read(page + i, 0x1000)); }
        const image = Buffer.concat(parts);
        const end = image.indexOf(Buffer.from([0x0d, 0xff]));
        if (image[0] !== 0x0d || end < 0) { throw new RemoteError('no program at PAGE'); }
        return detokenise(image.subarray(0, end + 2));
    }
}

/** BBC BASIC 5-byte real: exponent (excess 128), mantissa MSB first with
 *  the sign in its top bit (implied 1). */
export function bbcFloat(b: Uint8Array): number {
    if (b[0] === 0) { return 0; }
    let mant = ((b[1] << 24) >>> 0) + (b[2] << 16) + (b[3] << 8) + b[4];
    const sign = mant & 0x80000000 ? -1 : 1;
    mant = (mant | 0x80000000) >>> 0;
    const v = sign * mant / 2 ** 32 * 2 ** (b[0] - 128);
    return Number.isInteger(v) ? v : Number(v.toPrecision(10));
}

function latin1(text: string): number[] {
    return Array.from(text, ch => ch.charCodeAt(0) & 0xff);
}

const VDU_PARAMS = [0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 1, 2, 5, 0, 0, 1, 9, 8, 5, 0, 0, 4, 4, 0, 2];

/** Captured VDU bytes -> text: CR -> newline, VDU sequences dropped,
 *  prompt-only lines removed (as tools/u64remote.py clean_output). */
export function cleanOutput(raw: number[]): string {
    const out: string[] = [];
    for (let i = 0; i < raw.length; i++) {
        const b = raw[i];
        if (b === 13) { out.push('\n'); }
        else if (b === 10 || b === 127) { /* skip */ }
        else if (b < 32) { i += VDU_PARAMS[b]; }
        else if (b < 127) { out.push(String.fromCharCode(b)); }
    }
    return out.join('').split('\n').filter(l => l.trim() && l !== '>').map(l => l + '\n').join('');
}

function lastLine(text: string): string {
    const lines = text.split('\n').filter(l => l.trim());
    return lines.length ? lines[lines.length - 1].trim() : '';
}

/** Screen code -> ASCII for the MOS character set (tools/gentables.py). */
function screenChar(code: number): string {
    const c = code & 0x7f;
    const special: Record<number, string> = { 0x1c: '\\', 0x1e: '^', 0x1f: '_', 0x7a: '`',
                                              0x5b: '{', 0x69: '|', 0x5d: '}', 0x5e: '~',
                                              0x00: '@', 0x1b: '[', 0x1d: ']' };
    if (c in special) { return special[c]; }
    if (c >= 0x01 && c <= 0x1a) { return String.fromCharCode(c + 0x60); }
    if (c >= 0x41 && c <= 0x5a) { return String.fromCharCode(c); }
    if (c >= 0x20 && c <= 0x3f) { return String.fromCharCode(c); }
    return '#';
}
