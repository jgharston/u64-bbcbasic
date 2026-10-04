// Debug Adapter (Debug Adapter Protocol, inline) for U64 BBC BASIC.
//
// Uses the MOS's TRACE hook (docs/REMOTE_DEV.md): with TRACE ON BASIC
// reports each line before it runs; the MOS pauses at breakpoints or when
// stepping, and the variables are read from memory. One thread, one stack
// frame (the line about to run). BBC BASIC does not trace the first body
// line of a loop when NEXT/UNTIL jumps back to it: breakpoints there hit
// only on the first pass.

import * as vscode from 'vscode';
import { Remote, RunResult, DBG_CONTINUE, DBG_STEP } from './remote';

type Msg = { seq: number; type: string; command?: string; arguments?: any; event?: string };

export class BasicDebugSession implements vscode.DebugAdapter {
    private sendEmitter = new vscode.EventEmitter<any>();
    readonly onDidSendMessage = this.sendEmitter.event;
    private seq = 1;
    private remote?: Remote;
    private program = '';
    private sourcePath = '';
    private lines: string[] = [];
    private breakLines: number[] = [];               // BASIC line numbers
    private stopOnEntry = false;
    private configured = false;
    private launched = false;
    private currentLine = 0;
    private vars = new Map<string, number | string>();

    constructor(private remoteFactory: () => Remote, private timeout: () => number,
                private askInput: () => Thenable<string | undefined>) {}

    dispose() { this.sendEmitter.dispose(); }

    private send(msg: any) { this.sendEmitter.fire({ seq: this.seq++, ...msg }); }
    private respond(req: Msg, body: any = {}, success = true, message?: string) {
        this.send({ type: 'response', request_seq: req.seq, command: req.command, success, message, body });
    }
    private event(event: string, body: any = {}) { this.send({ type: 'event', event, body }); }
    private outputText(text: string, category = 'stdout') { this.event('output', { category, output: text }); }

    /** BASIC line number on an editor line (0-based), if any. */
    private basicLineAt(editorLine: number): number | undefined {
        const m = /^\s*(\d+)/.exec(this.lines[editorLine] ?? '');
        return m ? Number(m[1]) : undefined;
    }

    /** Editor line (0-based) holding a BASIC line number. */
    private editorLineOf(basicLine: number): number {
        const i = this.lines.findIndex(l => new RegExp(`^\\s*${basicLine}(?!\\d)`).test(l));
        return i < 0 ? 0 : i;
    }

    handleMessage(msg: Msg): void {
        this.dispatch(msg).catch(e => {
            this.respond(msg, {}, false, String(e?.message ?? e));
            if (msg.command === 'launch' || msg.command === 'configurationDone') { this.terminate(); }
        });
    }

    private async dispatch(req: Msg) {
        switch (req.command) {
        case 'initialize':
            this.respond(req, {
                supportsConfigurationDoneRequest: true,
                supportsTerminateRequest: true,
                supportsLoadedSourcesRequest: false,
            });
            this.event('initialized');
            break;
        case 'launch': {
            const a = req.arguments ?? {};
            this.sourcePath = a.program;
            this.stopOnEntry = !!a.stopOnEntry;
            const doc = await vscode.workspace.openTextDocument(this.sourcePath);
            this.program = doc.getText();
            this.lines = this.program.split(/\r?\n/);
            this.remote = this.remoteFactory();
            this.respond(req);
            this.launched = true;
            if (this.configured) { await this.start(); }
            break;
        }
        case 'setBreakpoints': {
            const want: { line: number }[] = req.arguments.breakpoints ?? [];
            if (!this.lines.length && req.arguments.source?.path) {
                const doc = await vscode.workspace.openTextDocument(req.arguments.source.path);
                this.lines = doc.getText().split(/\r?\n/);
            }
            const result: any[] = [];
            this.breakLines = [];
            for (const b of want) {
                const n = this.basicLineAt(b.line - 1);
                const ok = n !== undefined && this.breakLines.length < 8;
                if (ok) { this.breakLines.push(n!); }
                result.push({ verified: ok, line: b.line,
                              message: ok ? undefined : n === undefined ? 'no BASIC line number here'
                                                                        : 'at most 8 breakpoints' });
            }
            if (this.remote) { await this.remote.setBreakpoints(this.breakLines); }
            this.respond(req, { breakpoints: result });
            break;
        }
        case 'configurationDone':
            this.respond(req);
            this.configured = true;
            if (this.launched) { await this.start(); }
            break;
        case 'threads':
            this.respond(req, { threads: [{ id: 1, name: 'BBC BASIC' }] });
            break;
        case 'stackTrace': {
            const line = this.editorLineOf(this.currentLine);
            this.respond(req, { totalFrames: 1, stackFrames: [{
                id: 1, name: `line ${this.currentLine}`, line: line + 1, column: 1,
                source: { name: this.sourcePath.split(/[\\/]/).pop(), path: this.sourcePath } }] });
            break;
        }
        case 'scopes':
            this.respond(req, { scopes: [
                { name: 'Variables', variablesReference: 1, expensive: false },
                { name: 'Resident integers', variablesReference: 2, expensive: false }] });
            break;
        case 'variables': {
            const resident = req.arguments.variablesReference === 2;
            const list = [...this.vars.entries()]
                .filter(([k]) => /^[@A-Z]%$/.test(k) === resident)
                .map(([k, v]) => ({ name: k, value: typeof v === 'string' && k.endsWith('$') ? JSON.stringify(v) : String(v),
                                    variablesReference: 0 }));
            this.respond(req, { variables: list });
            break;
        }
        case 'continue':
            this.respond(req, { allThreadsContinued: true });
            await this.resume(DBG_CONTINUE);
            break;
        case 'next': case 'stepIn': case 'stepOut':
            this.respond(req);
            await this.resume(DBG_STEP);
            break;
        case 'pause':
            await this.remote?.requestPause();
            this.respond(req);
            break;
        case 'disconnect': case 'terminate':
            try { await this.remote?.stop(); await this.remote?.debugEnd(); } catch { /* gone */ }
            this.respond(req);
            if (req.command === 'terminate') { this.event('terminated'); }
            break;
        default:
            this.respond(req, {}, false, `not supported: ${req.command}`);
        }
    }

    private async start() {
        if (!this.remote) { return; }
        this.launched = false;                       // start once
        this.outputText(`RUN ${this.sourcePath.split(/[\\/]/).pop()} on ${this.remote.host}\n`, 'console');
        const r = await this.remote.debugStart(this.program, this.breakLines, this.stopOnEntry,
                                               this.timeout(), t => this.outputText(t));
        await this.handle(r, this.stopOnEntry ? 'entry' : 'breakpoint');
    }

    private async resume(how: number) {
        if (!this.remote) { return; }
        const r = await this.remote.debugResume(how, this.timeout(), t => this.outputText(t));
        await this.handle(r, how === DBG_STEP ? 'step' : 'breakpoint');
    }

    private async handle(r: RunResult, reason: string) {
        if (!this.remote) { return; }
        if (r.state === 'paused') {
            this.currentLine = r.line ?? (await this.remote.state()).line;
            this.vars = await this.remote.variables();
            this.event('stopped', { reason, threadId: 1, allThreadsStopped: true });
            return;
        }
        if (r.state === 'input') {
            const answer = await this.askInput();
            if (answer === undefined) { await this.remote.stop(); await this.terminate(); return; }
            this.outputText(answer + '\n', 'console');
            const next = await this.remote.runLines([answer], this.timeout(), t => this.outputText(t));
            await this.handle(next, reason);
            return;
        }
        if (r.state === 'timeout') {
            // still running: keep waiting for a breakpoint or the end
            const next = await this.remote.runLines([], this.timeout(), t => this.outputText(t),
                                                     { errorsBefore: (await this.remote.state()).errorCount });
            await this.handle(next, reason);
            return;
        }
        if (r.error) {
            this.outputText(`${r.error.message}${r.error.line !== null ? ' at line ' + r.error.line : ''} (error ${r.error.number})\n`, 'stderr');
        }
        await this.terminate();
    }

    private async terminate() {
        try { await this.remote?.debugEnd(); } catch { /* gone */ }
        this.event('terminated');
    }
}
