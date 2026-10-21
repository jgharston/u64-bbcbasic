// Indentation of BBC BASIC source by block nesting (docs/PLAN.md section 2):
// the line number, one space, then 2 spaces per level. Blocks: FOR/NEXT,
// REPEAT/UNTIL, DEF PROC/ENDPROC, DEF FN/the "=" line that returns. Only
// statements at the start of a statement count; after IF the rest of the
// line is conditional (IF X THEN ENDPROC ends no block); REM, DATA, strings
// and * commands are not looked into. A line that starts by closing a block
// is indented one level less (the UNTIL under its REPEAT).
// The indentation costs memory on the machine, so sendProgram strips it
// again (tokenizer.ts, as tools/bbctok.py); LISTO 7 indents loops there.

const OPENERS = /^(FOR\b|REPEAT\b|DEF\s*PROC|DEF\s*FN)/;
const CLOSERS = /^(NEXT\b|UNTIL\b|ENDPROC\b|=)/;

/** Statements of a line body that count for nesting (split at ':' outside strings). */
function statements(body: string): string[] {
    const out: string[] = [];
    let cur = '';
    let quote = false;
    for (let i = 0; i < body.length; i++) {
        const c = body[i];
        if (c === '"') { quote = !quote; }
        if (c === ':' && !quote) { out.push(cur.trim()); cur = ''; continue; }
        cur += c;
    }
    out.push(cur.trim());
    return out;
}

/** A DEF FN that returns on its own line (DEF FNsq(x)=x*x) opens no block. */
function singleLineFn(stmt: string): boolean {
    let depth = 0;
    let quote = false;
    for (const c of stmt) {
        if (c === '"') { quote = !quote; }
        if (quote) { continue; }
        if (c === '(') { depth++; }
        if (c === ')') { depth--; }
        if (c === '=' && depth === 0) { return true; }
    }
    return false;
}

/** Opens and closes of one line body; leading: closes before any open. */
function nesting(body: string): { opens: number; closes: number; leading: number } {
    let opens = 0, closes = 0, leading = 0;
    // REPEAT may be followed by a statement without a colon (REPEAT UNTIL
    // TIME>T%): what comes after it is a statement of its own
    const list: string[] = [];
    for (let st of statements(body)) {
        while (/^REPEAT\b/i.test(st)) {
            list.push('REPEAT');
            st = st.slice(6).trim();
        }
        if (st) { list.push(st); }
    }
    for (const s of list) {
        const u = s.toUpperCase();
        if (/^(REM|DATA|\*)/.test(u)) { break; }
        if (CLOSERS.test(u)) {
            closes++;
            if (opens === 0) { leading++; }
        } else if (OPENERS.test(u)) {
            if (/^DEF\s*FN/.test(u) && singleLineFn(s)) { continue; }
            opens++;
        }
        if (/^IF\b/.test(u) || /\bTHEN\b/.test(u) || /\bELSE\b/.test(u)) { break; }
    }
    return { opens, closes, leading };
}

/** The program text indented by nesting; lines without a number stay as they are. */
export function formatProgram(text: string): string {
    const eol = text.includes('\r\n') ? '\r\n' : '\n';
    let level = 0;
    const out = text.split(/\r?\n/).map(line => {
        const m = /^\s*(\d+)\s*(.*?)\s*$/.exec(line);
        if (!m) { return line; }
        const [, number, body] = m;
        if (!body) { return number; }
        const n = nesting(body);
        const indent = Math.max(0, level - n.leading);
        level = Math.max(0, level + n.opens - n.closes);
        return `${number} ${'  '.repeat(indent)}${body}`;
    });
    return out.join(eol);
}

/** The indentation taken out again (spaces after the line number beyond one). */
export function stripIndent(line: string): string {
    return line.replace(/^(\s*\d+) +/, '$1 ');
}
