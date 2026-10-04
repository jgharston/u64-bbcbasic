// Runs inside VS Code (see runIntegration.ts): the extension's commands
// and language features end to end, against the machine in U64_HOST.
import * as assert from 'assert';
import * as vscode from 'vscode';

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

async function open(text: string) {
    const doc = await vscode.workspace.openTextDocument({ language: 'bbcbasic', content: text });
    await vscode.window.showTextDocument(doc);
    return doc;
}

export async function run(): Promise<void> {
    const results: string[] = [];
    const check = (name: string, ok: boolean, detail?: unknown) => {
        results.push(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : ' ' + JSON.stringify(detail)}`);
    };
    const ext = vscode.extensions.getExtension('xahmol.u64-bbcbasic');
    await ext!.activate();
    check('activates', ext!.isActive);

    const cmds = await vscode.commands.getCommands(true);
    check('commands registered', ['u64bbc.run', 'u64bbc.stop', 'u64bbc.getProgram'].every(c => cmds.includes(c)));

    // language: hover help from *HELP
    let doc = await open('10 PRINT "HELLO"\n');
    const hovers = await vscode.commands.executeCommand<vscode.Hover[]>(
        'vscode.executeHoverProvider', doc.uri, new vscode.Position(0, 4));
    const hoverText = hovers.map(h => h.contents.map(c => (c as vscode.MarkdownString).value).join('')).join('');
    check('hover help for PRINT', hoverText.includes('Prints values'), hoverText.slice(0, 80));

    // offline check: a descending line number is a problem
    doc = await open('20 PRINT 1\n10 END\n');
    await vscode.commands.executeCommand('u64bbc.check');
    const diags = vscode.languages.getDiagnostics(doc.uri);
    check('check marks a bad line number', diags.length === 1 && diags[0].range.start.line === 1, diags);

    const host = process.env.U64_HOST;
    if (host) {
        await vscode.workspace.getConfiguration('u64bbc').update('host', host, vscode.ConfigurationTarget.Global);
        await vscode.workspace.getConfiguration('u64bbc').update('promptForInput', false, vscode.ConfigurationTarget.Global);
        // run: a run-time error lands on its source line
        doc = await open('10 PRINT "FROM VSCODE"\n20 X=1/0\n30 END\n');
        await vscode.commands.executeCommand('u64bbc.run');
        await sleep(500);
        const d = vscode.languages.getDiagnostics(doc.uri);
        check('run: error 18 on line 20', d.length === 1 && d[0].range.start.line === 1 &&
              d[0].message.includes('Division by zero'), d);
        // get the program back
        await vscode.commands.executeCommand('u64bbc.getProgram');
        const back = vscode.window.activeTextEditor?.document.getText() ?? '';
        check('program read back', back.startsWith('10 PRINT "FROM VSCODE"'), back);
        // debugger: breakpoint, variables, step, continue to the end
        doc = await open('10 A%=5:B=1.5:C$="TEXT"\n20 FOR I%=1 TO 3\n30 PRINT "I=";I%\n40 NEXT\n50 X=A%*B\n60 END\n');
        const fs = await import('fs');
        const os = await import('os');
        const path = await import('path');
        const file = path.join(os.tmpdir(), 'u64dbg.bas');
        fs.writeFileSync(file, doc.getText());
        const fileDoc = await vscode.workspace.openTextDocument(file);
        await vscode.window.showTextDocument(fileDoc);
        vscode.debug.addBreakpoints([new vscode.SourceBreakpoint(new vscode.Location(fileDoc.uri, new vscode.Position(3, 0)))]);
        const stops: number[] = [];
        let terminated = false;
        const tracker = vscode.debug.registerDebugAdapterTrackerFactory('u64bbc', { createDebugAdapterTracker: () => ({
            onDidSendMessage: (m: any) => {
                if (m.type === 'event' && m.event === 'stopped') { stops.push(Date.now()); }
                if (m.type === 'event' && m.event === 'terminated') { terminated = true; }
            } }) });
        await vscode.debug.startDebugging(undefined, { type: 'u64bbc', request: 'launch', name: 'test', program: file });
        for (let i = 0; i < 100 && !stops.length; i++) { await sleep(200); }
        const session = vscode.debug.activeDebugSession!;
        const st = await session.customRequest('stackTrace', { threadId: 1 });
        check('debug: paused on line 40', stops.length === 1 && st.stackFrames[0].line === 4, st);
        const vars = await session.customRequest('variables', { variablesReference: 1 });
        const res = await session.customRequest('variables', { variablesReference: 2 });
        const all = [...vars.variables, ...res.variables].map((v: any) => `${v.name}=${v.value}`);
        check('debug: variables', ['A%=5', 'I%=1', 'B=1.5', 'C$="TEXT"'].every(x => all.includes(x)), all);
        await session.customRequest('next', { threadId: 1 });
        for (let i = 0; i < 50 && stops.length < 2; i++) { await sleep(200); }
        check('debug: step stops again', stops.length === 2);
        vscode.debug.removeBreakpoints(vscode.debug.breakpoints);
        await sleep(300);
        await session.customRequest('continue', { threadId: 1 });
        for (let i = 0; i < 100 && !terminated; i++) { await sleep(200); }
        check('debug: runs to the end', terminated);
        tracker.dispose();
    } else {
        results.push('skip machine tests (no U64_HOST)');
    }

    console.log('\n' + results.join('\n'));
    if (results.some(r => r.startsWith('FAIL'))) { throw new Error('extension tests failed'); }
}
