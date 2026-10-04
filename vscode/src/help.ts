// The *HELP reference (src/help/help.txt, packed by tools/genextdata.py)
// for hovers and completion: the same text the cartridge shows.

import * as helpData from '../data/help.json';

export interface HelpEntry { names: string[]; kind: 'keyword' | 'command' | 'topic'; text: string; }

export const HELP: HelpEntry[] = (helpData as any).default ?? (helpData as any);

const BY_NAME = new Map<string, HelpEntry>();
for (const e of HELP) { for (const n of e.names) { BY_NAME.set(n.toUpperCase(), e); } }

/** Help for a word as written in a program (KEYWORD, CHR$, *CAT, ...). */
export function lookup(word: string): HelpEntry | undefined {
    const w = word.toUpperCase();
    return BY_NAME.get(w) ?? BY_NAME.get(w.replace(/\($/, '')) ?? BY_NAME.get(w + '#');
}

export function keywords(): HelpEntry[] { return HELP.filter(e => e.kind === 'keyword'); }
export function commands(): HelpEntry[] { return HELP.filter(e => e.kind === 'command'); }
