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
    } else {
        results.push('skip machine tests (no U64_HOST)');
    }

    console.log('\n' + results.join('\n'));
    if (results.some(r => r.startsWith('FAIL'))) { throw new Error('extension tests failed'); }
}
