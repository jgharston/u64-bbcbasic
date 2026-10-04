// U64 BBC BASIC for VS Code: write BBC BASIC on the PC, run it on an
// Ultimate 64 / C64 Ultimate through the MOS mailbox (docs/REMOTE_DEV.md).

import * as vscode from 'vscode';
import { Remote, RunResult, RemoteError } from './remote';
import { tokeniseProgram, TokeniseError } from './tokenizer';
import { lookup, keywords, commands } from './help';
import { BasicDebugSession } from './debugAdapter';

const LANG = 'bbcbasic';
let output: vscode.OutputChannel;
let status: vscode.StatusBarItem;
let diagnostics: vscode.DiagnosticCollection;
let busy = false;

function config() { return vscode.workspace.getConfiguration('u64bbc'); }

function remote(): Remote {
    const host = config().get<string>('host', '').trim();
    if (!host) {
        throw new RemoteError('No machine set: run "U64 BBC BASIC: Select Machine" or set u64bbc.host');
    }
    return new Remote(host, config().get<string>('password') || undefined);
}

function setStatus(text: string, tooltip?: string) {
    status.text = `$(device-desktop) U64: ${text}`;
    status.tooltip = tooltip ?? config().get<string>('host');
    status.show();
}

async function guarded(title: string, f: () => Promise<void>) {
    if (busy) { vscode.window.showWarningMessage('U64 BBC BASIC: still busy with the previous command'); return; }
    busy = true;
    try {
        await vscode.window.withProgress({ location: vscode.ProgressLocation.Window, title }, f);
    } catch (e: any) {
        setStatus('error', e.message);
        vscode.window.showErrorMessage(`U64 BBC BASIC: ${e.message}`);
    } finally {
        busy = false;
    }
}

// --- diagnostics ----------------------------------------------------------------

/** Check the program offline; mark tokeniser problems. Returns the text or
 *  undefined when it cannot be sent. */
function checkDocument(doc: vscode.TextDocument): string | undefined {
    diagnostics.delete(doc.uri);
    try {
        tokeniseProgram(doc.getText());
        return doc.getText();
    } catch (e) {
        if (e instanceof TokeniseError) {
            const line = doc.lineAt(e.sourceLine);
            diagnostics.set(doc.uri, [new vscode.Diagnostic(line.range, e.message,
                                                             vscode.DiagnosticSeverity.Error)]);
            return undefined;
        }
        throw e;
    }
}

/** Put a BASIC run-time error on the source line with that line number. */
function markRuntimeError(doc: vscode.TextDocument, r: RunResult) {
    if (!r.error || r.error.line === null) { return; }
    const re = new RegExp(`^\\s*${r.error.line}(?!\\d)`);
    for (let n = 0; n < doc.lineCount; n++) {
        if (re.test(doc.lineAt(n).text)) {
            const d = new vscode.Diagnostic(doc.lineAt(n).range,
                `${r.error.message} (error ${r.error.number})`, vscode.DiagnosticSeverity.Error);
            d.source = 'U64 BBC BASIC';
            diagnostics.set(doc.uri, [d]);
            return;
        }
    }
}

// --- running --------------------------------------------------------------------

async function report(r: RunResult, doc?: vscode.TextDocument) {
    if (r.error) {
        output.appendLine(`[error ${r.error.number}: ${r.error.message}${r.error.line !== null ? ' at line ' + r.error.line : ''}]`);
        if (doc) { markRuntimeError(doc, r); }
        setStatus('error', r.error.message);
    } else {
        setStatus(r.state);
    }
    if (r.state === 'timeout') {
        output.appendLine('[still running: "U64 BBC BASIC: Stop" sends ESCAPE]');
    }
    if (r.state === 'input' && config().get<boolean>('promptForInput', true)) {
        await answerInput(doc);
    }
}

async function answerInput(doc?: vscode.TextDocument) {
    const text = await vscode.window.showInputBox({ prompt: 'The program waits for INPUT',
                                                    placeHolder: 'answer (Escape: leave it waiting)' });
    if (text === undefined) { setStatus('input'); return; }
    output.appendLine(`> ${text}`);
    setStatus('running');
    const r = await remote().runLines([text], timeout(), t => output.append(t));
    await report(r, doc);
}

function timeout() { return config().get<number>('timeout', 30) * 1000; }

async function sendDocument(run: boolean) {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== LANG) {
        vscode.window.showWarningMessage('Open a BBC BASIC file (.bas) first.');
        return;
    }
    const doc = editor.document;
    const text = checkDocument(doc);
    if (text === undefined) { return; }
    await guarded(run ? 'Running on U64' : 'Sending to U64', async () => {
        output.show(true);
        output.appendLine(`--- ${run ? 'RUN' : 'LOAD'} ${vscode.workspace.asRelativePath(doc.uri)} on ${config().get('host')}`);
        setStatus(run ? 'running' : 'sending');
        const r = await remote().sendProgram(text, run, timeout(), t => output.append(t));
        output.appendLine(`[${r.programBytes} bytes, ${r.elapsed.toFixed(2)} s, ${r.state}]`);
        await report(r, doc);
    });
}

async function typeLine() {
    const line = await vscode.window.showInputBox({ prompt: 'Line to type at the BBC BASIC prompt',
                                                    placeHolder: 'PRINT 6*7   or   *CAT' });
    if (!line) { return; }
    await guarded('U64: typing', async () => {
        output.show(true);
        output.appendLine(`> ${line}`);
        const r = await remote().runLines([line], timeout(), t => output.append(t));
        await report(r);
    });
}

async function getProgram() {
    await guarded('U64: reading the program', async () => {
        const text = await remote().programText();
        const doc = await vscode.workspace.openTextDocument({ language: LANG, content: text });
        await vscode.window.showTextDocument(doc);
    });
}

async function showScreen() {
    await guarded('U64: reading the screen', async () => {
        const rows = await remote().screen();
        output.show(true);
        output.appendLine('+' + '-'.repeat(40) + '+');
        for (const r of rows) { output.appendLine('|' + r.padEnd(40) + '|'); }
        output.appendLine('+' + '-'.repeat(40) + '+');
    });
}

async function stop() {
    await guarded('U64: ESCAPE', async () => {
        await remote().stop();
        setStatus('stopped');
    });
}

async function selectMachine() {
    const host = await vscode.window.showInputBox({ prompt: 'IP address or host name of the Ultimate',
                                                    value: config().get<string>('host', '') });
    if (!host) { return; }
    await config().update('host', host.trim(), vscode.ConfigurationTarget.Global);
    await guarded('U64: connecting', async () => {
        const r = remote();
        const info = await r.info();
        const st = await r.state();
        setStatus(st.state, `${info.product} (firmware ${info.firmware_version}) at ${host}`);
        vscode.window.showInformationMessage(`U64 BBC BASIC on ${info.product} at ${host}: ${st.state}`);
    });
}

async function refreshStatus() {
    await guarded('U64: status', async () => {
        const st = await remote().state();
        setStatus(st.state);
    });
}

// --- language features ----------------------------------------------------------

const WORD = /\*?[A-Za-z][A-Za-z0-9_]*[$#(]?/;

function hoverProvider(): vscode.HoverProvider {
    return {
        provideHover(doc, pos) {
            const range = doc.getWordRangeAtPosition(pos, WORD);
            if (!range) { return; }
            let word = doc.getText(range);
            // keywords are upper case; a lower-case word is a variable
            if (word.replace(/^\*/, '') !== word.replace(/^\*/, '').toUpperCase() && !word.startsWith('*')) { return; }
            let entry = lookup(word);
            // a keyword followed directly by more letters (PRINTA): try prefixes
            for (let n = word.length - 1; !entry && n > 1; n--) { entry = lookup(word.slice(0, n)); }
            if (!entry) { return; }
            const md = new vscode.MarkdownString();
            md.appendMarkdown(`**${entry.names[0]}**${entry.names.length > 1 ? ' (' + entry.names.slice(1).join(', ') + ')' : ''}\n\n`);
            md.appendCodeblock(entry.text, 'text');
            return new vscode.Hover(md, range);
        },
    };
}

function completionProvider(): vscode.CompletionItemProvider {
    const items: vscode.CompletionItem[] = [];
    for (const e of keywords()) {
        const it = new vscode.CompletionItem(e.names[0], vscode.CompletionItemKind.Keyword);
        it.documentation = new vscode.MarkdownString().appendCodeblock(e.text, 'text');
        items.push(it);
    }
    for (const e of commands()) {
        const it = new vscode.CompletionItem(e.names[0], vscode.CompletionItemKind.Function);
        it.documentation = new vscode.MarkdownString().appendCodeblock(e.text, 'text');
        items.push(it);
    }
    return { provideCompletionItems() { return items; } };
}

// --- activation -----------------------------------------------------------------

export function activate(context: vscode.ExtensionContext) {
    output = vscode.window.createOutputChannel('U64 BBC BASIC');
    status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
    status.command = 'u64bbc.status';
    diagnostics = vscode.languages.createDiagnosticCollection('u64bbc');
    setStatus(config().get<string>('host') ? 'ready' : 'no machine');

    const cmd = (id: string, f: () => any) =>
        context.subscriptions.push(vscode.commands.registerCommand(id, f));
    cmd('u64bbc.run', () => sendDocument(true));
    cmd('u64bbc.send', () => sendDocument(false));
    cmd('u64bbc.stop', stop);
    cmd('u64bbc.typeLine', typeLine);
    cmd('u64bbc.answerInput', () => guarded('U64: INPUT', () => answerInput()));
    cmd('u64bbc.getProgram', getProgram);
    cmd('u64bbc.screen', showScreen);
    cmd('u64bbc.selectMachine', selectMachine);
    cmd('u64bbc.status', refreshStatus);
    cmd('u64bbc.check', () => {
        const doc = vscode.window.activeTextEditor?.document;
        if (doc && checkDocument(doc) !== undefined) {
            vscode.window.showInformationMessage(`${tokeniseProgram(doc.getText()).image.length} bytes tokenised, no problems.`);
        }
    });

    // F5: debug with breakpoints (TRACE hook); a .bas file without a
    // launch.json debugs the file in the editor
    context.subscriptions.push(
        vscode.debug.registerDebugAdapterDescriptorFactory('u64bbc', {
            createDebugAdapterDescriptor: () => new vscode.DebugAdapterInlineImplementation(
                new BasicDebugSession(remote, timeout,
                    () => vscode.window.showInputBox({ prompt: 'The program waits for INPUT' }))),
        }),
        vscode.debug.registerDebugConfigurationProvider('u64bbc', {
            resolveDebugConfiguration(_folder, cfg) {
                if (!cfg.type && !cfg.request) {
                    const doc = vscode.window.activeTextEditor?.document;
                    if (!doc || doc.languageId !== LANG) { return undefined; }
                    cfg = { type: 'u64bbc', request: 'launch', name: 'Debug on U64' };
                }
                cfg.program = cfg.program || vscode.window.activeTextEditor?.document.uri.fsPath;
                if (!cfg.program) { return undefined; }
                return cfg;
            },
        }),
    );

    context.subscriptions.push(
        output, status, diagnostics,
        vscode.languages.registerHoverProvider(LANG, hoverProvider()),
        vscode.languages.registerCompletionItemProvider(LANG, completionProvider()),
        vscode.workspace.onDidSaveTextDocument(doc => { if (doc.languageId === LANG) { checkDocument(doc); } }),
        vscode.workspace.onDidChangeTextDocument(e => diagnostics.delete(e.document.uri)),
    );
}

export function deactivate() {}
