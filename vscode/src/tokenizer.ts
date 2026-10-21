// BBC BASIC 3.10 tokeniser and detokeniser.
//
// TypeScript port of tools/bbctok.py, which is itself a port of the
// interpreter's MATCH routine (ivop/bbc-basic basic.s, "Tokenise line at
// (zpWORK)", and CONSTQ/CONSTI). Kept line for line parallel to the
// Python; test/tokenizer.test.js checks both give the same bytes, and the
// E2E test remote_tokeniser checks the Python against the interpreter.

import * as tokenTable from '../data/tokens.json';
import { stripIndent } from './formatter';

export interface Token { keyword: string; token: number; flags: number; }

export const TOKENS: Token[] = (tokenTable as any).default ?? (tokenTable as any);

const CR = 0x0d;
const TKN_CONST = 0x8d;
const PSEUDO_OFFSET = 0x40;          // tknPTR2 - tknPTR

const DETOKEN = new Map<number, string>();
for (const t of TOKENS) {
    if (!DETOKEN.has(t.token)) { DETOKEN.set(t.token, t.keyword); }
    if (t.flags & 0x40 && !DETOKEN.has(t.token + PSEUDO_OFFSET)) {
        DETOKEN.set(t.token + PSEUDO_OFFSET, t.keyword);
    }
}

/** WORDCQ: digits, A-Z, _, ` and a-z. */
function isWord(c: number): boolean {
    return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x5f && c <= 0x7a);
}

function isDigit(c: number): boolean {
    return c >= 0x30 && c <= 0x39;
}

/** CONSTI: 3 bytes for a line number constant (0-32767). */
export function encodeLineNumber(n: number): number[] {
    const lo = n & 0xff, hi = n >> 8;
    const b1 = ((((lo & 0xc0) | ((hi & 0xc0) >> 2)) >> 2) ^ 0x54) & 0xff;
    return [b1, (lo & 0x3f) | 0x40, (hi & 0x3f) | 0x40];
}

/** SPGETN. */
export function decodeLineNumber(b1: number, b2: number, b3: number): number {
    const x = (b1 << 2) & 0xff;
    const lo = (x & 0xc0) ^ b2;
    const hi = (((x << 2) & 0xff) ^ b3) & 0xff;
    return lo | (hi << 8);
}

function latin1(text: string): number[] {
    const out: number[] = [];
    for (const ch of text) { out.push(ch.charCodeAt(0) & 0xff); }
    return out;
}

/** MATCHA on one line (no CR): the tokenised bytes. */
export function tokeniseLine(text: string, start = true, lineno = true): number[] {
    const buf = latin1(text);
    buf.push(CR);
    let i = 0;
    const ymatch = () => { start = false; lineno = false; };

    for (;;) {
        const c = buf[i];
        if (c === CR) { break; }
        if (c === 0x20) { i++; continue; }
        if (c === 0x26) {                                  // & hex
            i++;
            while (isDigit(buf[i]) || (buf[i] >= 0x41 && buf[i] <= 0x46)) { i++; }
            continue;
        }
        if (c === 0x22) {                                  // string
            i++;
            while (buf[i] !== 0x22 && buf[i] !== CR) { i++; }
            if (buf[i] === CR) { break; }
            i++;
            continue;
        }
        if (c === 0x3a) { start = true; lineno = false; i++; continue; }     // :
        if (c === 0x2c) { i++; continue; }                                    // ,
        if (c === 0x2a) {                                  // *
            if (start) { break; }
            ymatch(); i++; continue;
        }
        if (c === 0x2e || isDigit(c)) {                    // . or digit
            if (c !== 0x2e && lineno) {
                let j = i, n = 0, ok = true;
                while (isDigit(buf[j])) {
                    n = n * 10 + buf[j] - 0x30;
                    if (n >= 32768) { ok = false; }
                    j++;
                }
                if (ok) {
                    buf.splice(i, j - i, TKN_CONST, ...encodeLineNumber(n));
                    i += 4;
                    continue;
                }
            }
            while (buf[i] === 0x2e || isDigit(buf[i])) { i++; }
            ymatch();
            continue;
        }
        if (c < 0x41) { ymatch(); i++; continue; }
        if (c >= 0x58) {                                   // X..: no keywords
            if (!isWord(c)) { ymatch(); i++; continue; }
            while (isWord(buf[i])) { i++; }
            ymatch();
            continue;
        }
        let found: { tok: number; flags: number; used: number } | undefined;
        for (const t of TOKENS) {
            const k = latin1(t.keyword);
            if (c < k[0]) { break; }
            if (c !== k[0]) { continue; }
            let j = 1;
            while (j < k.length && buf[i + j] === k[j]) { j++; }
            if (j === k.length) { found = { tok: t.token, flags: t.flags, used: j }; break; }
            if (buf[i + j] === 0x2e) { found = { tok: t.token, flags: t.flags, used: j + 1 }; break; }
        }
        if (!found) {
            while (isWord(buf[i])) { i++; }
            ymatch();
            continue;
        }
        let { tok } = found;
        const { flags, used } = found;
        if ((flags & 0x01) && isWord(buf[i + used])) {     // conditional
            while (isWord(buf[i])) { i++; }
            ymatch();
            continue;
        }
        if ((flags & 0x40) && start) { tok += PSEUDO_OFFSET; }
        buf.splice(i, used, tok);
        if (flags & 0x02) { start = false; lineno = false; }
        if (flags & 0x04) { start = true; lineno = false; }
        if (flags & 0x08) { while (isWord(buf[i + 1])) { i++; } }
        if (flags & 0x10) { lineno = true; }
        if (flags & 0x20) { break; }
        i++;
    }
    return buf.slice(0, buf.indexOf(CR));
}

export class TokeniseError extends Error {
    constructor(message: string, public sourceLine: number) { super(message); }
}

export interface ProgramLine { number: number; sourceLine: number; }

/** Program text -> image as stored at PAGE (CR ... CR &FF). The source's
 * indentation (spaces after the line number beyond one) is dropped unless
 * keepIndent: it costs memory, and LISTO 7 indents on the machine
 * (as tools/bbctok.py's tokenise_program). */
export function tokeniseProgram(text: string, keepIndent = false): { image: Uint8Array; lines: ProgramLine[] } {
    const image: number[] = [CR];
    const lines: ProgramLine[] = [];
    let last = -1;
    const src = text.split(/\r?\n/);
    for (let n = 0; n < src.length; n++) {
        let raw = src[n].replace(/\s+$/, '');
        if (!keepIndent) { raw = stripIndent(raw); }
        if (!raw.trim()) { continue; }
        const tok = tokeniseLine(raw);
        let k = 0;
        while (k < tok.length && tok[k] === 0x20) { k++; }
        if (k >= tok.length || tok[k] !== TKN_CONST) {
            throw new TokeniseError('no line number', n);
        }
        const number = decodeLineNumber(tok[k + 1], tok[k + 2], tok[k + 3]);
        if (number <= last) {
            throw new TokeniseError(`line number ${number} not ascending (after ${last})`, n);
        }
        const body = tok.slice(k + 4);
        if (body.length + 4 > 255) {
            throw new TokeniseError('line too long (BBC BASIC: 251 characters tokenised)', n);
        }
        image.push(number >> 8, number & 0xff, body.length + 4, ...body, CR);
        lines.push({ number, sourceLine: n });
        last = number;
    }
    image.push(0xff);
    return { image: Uint8Array.from(image), lines };
}

/** Program image -> text, as LIST shows it (no LISTO formatting). */
export function detokenise(image: Uint8Array): string {
    const out: string[] = [];
    let i = 1;
    while (i < image.length && image[i] !== 0xff) {
        const number = (image[i] << 8) | image[i + 1];
        const length = image[i + 2];
        const body = image.slice(i + 3, i + length - 1);
        const line: string[] = [];
        let quote = false;
        for (let j = 0; j < body.length; j++) {
            const b = body[j];
            if (b === 0x22) { quote = !quote; }
            if (!quote && b === TKN_CONST) {
                line.push(String(decodeLineNumber(body[j + 1], body[j + 2], body[j + 3])));
                j += 3;
                continue;
            }
            const kw = DETOKEN.get(b);
            if (!quote && b >= 0x80 && kw) {
                line.push(kw);
                if (kw === 'REM' || kw === 'DATA') {
                    line.push(String.fromCharCode(...body.slice(j + 1)));
                    break;
                }
            } else {
                line.push(String.fromCharCode(b));
            }
        }
        out.push(`${number}${line.join('')}`);
        i += length;
    }
    return out.join('\n') + '\n';
}
