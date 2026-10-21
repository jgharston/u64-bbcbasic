// The VS Code scene of video 1 (docs/VIDEO_PLAN.md), run inside VS Code by
// the driver extension (extension.js; tools/video/v1_vscode.py starts it). Every step
// goes through the editor's own commands, so the window shows what a user
// would see; each step is logged with its wall-clock time to
// $U64_VIDEO_EVENTS for the edit. Pattern from the extension's
// integration test (vscode/test/suite/index.ts).
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');

const http = require('http');

const sleep = ms => new Promise(r => setTimeout(r, ms));
const events = [];
const ev = (kind, extra) => {
    events.push(Object.assign({ epoch: Date.now() / 1000, kind }, extra || {}));
    fs.writeFileSync(process.env.U64_VIDEO_EVENTS, JSON.stringify(events, null, 1));
};

const RINGS = [
    '10 MODE 1', '20 PROCrings(640,512)', '30 REPEAT UNTIL GET', '40 END',
    '50 DEF PROCrings(X%,Y%)', '60 LOCAL R%', '70 FOR R%=40 TO 400 STEP 40',
    '80 GCOL 0,R% DIV 40 MOD 3+1', '90 PROCcircle(X%,Y%,R%)', '100 NEXT',
    '110 ENDPROC', '120 DEF PROCcircle(X%,Y%,R%)', '130 LOCAL A',
    '140 MOVE X%+R%,Y%', '150 FOR A=0 TO 2*PI+0.1 STEP PI/16',
    '160 DRAW X%+R%*COS A,Y%+R%*SIN A', '170 NEXT', '180 ENDPROC',
];

// a key tap on the U64's keyboard matrix (ends REPEAT UNTIL GET without
// the Escape error that Stop would leave in Problems)
function tapKey(key) {
    const body = JSON.stringify({ events: [{ kind: 'keyboard', inputs: [key], transition: 'tap' }] });
    return new Promise((resolve, reject) => {
        const req = http.request({ host: process.env.U64_HOST, path: '/v1/machine:input', method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } },
            res => { res.resume(); res.on('end', resolve); });
        req.on('error', reject);
        req.end(body);
    });
}

async function typeText(text, ms) {
    for (const ch of text) {
        await vscode.commands.executeCommand('type', { text: ch });
        await sleep(ms + Math.random() * ms);
    }
}

async function openFile(file) {
    const doc = await vscode.workspace.openTextDocument(file);
    await vscode.window.showTextDocument(doc);
    return doc;
}

exports.run = async function () {
    const dir = vscode.workspace.workspaceFolders[0].uri.fsPath;
    const ext = vscode.extensions.getExtension('xahmol.u64-bbcbasic');
    await ext.activate();
    // every debug protocol message, for the event log
    vscode.debug.registerDebugAdapterTrackerFactory('u64bbc', { createDebugAdapterTracker: () => ({
        onWillReceiveMessage: m => ev('dap>', { m: m.command }),
        onDidSendMessage: m => ev('dap<', { m: m.type === 'event' ? 'event ' + m.event : 'response ' + m.command,
                                           ok: m.success, body: m.type === 'event' ? m.body : undefined }),
        onError: e => ev('dap error', { e: String(e) }),
    }) });
    const scenes = (process.env.U64_VIDEO_SCENES || 'all').split(',');
    const want = s => scenes.includes('all') || scenes.includes(s);
    ev('ready');
    await sleep(9000);              // the window capture starts
    if (want('edit')) { await editScenes(dir); }
    if (want('debug')) { await debugScene(dir); }
    ev('end');
};

async function editScenes(dir) {

    // typing, unindented
    ev('scene', { name: 'vsc_type' });
    const doc = await openFile(path.join(dir, 'rings.bas'));
    await sleep(1500);
    for (const line of RINGS) {
        await typeText(line + '\n', 25);
    }
    await sleep(1500);

    // Format Document indents the loops and procedures
    ev('scene', { name: 'vsc_format' });
    await vscode.commands.executeCommand('editor.action.formatDocument');
    await sleep(3500);
    ev('text', { text: doc.getText() });
    await doc.save();

    // hover help from *HELP
    ev('scene', { name: 'vsc_hover' });
    const editor = vscode.window.activeTextEditor;
    const drawLine = doc.getText().split('\n').findIndex(l => l.includes('DRAW'));
    if (drawLine >= 0) {
        const col = doc.lineAt(drawLine).text.indexOf('DRAW') + 1;
        editor.selection = new vscode.Selection(drawLine, col, drawLine, col);
        await vscode.commands.executeCommand('editor.action.showHover');
        await sleep(5000);
        await vscode.commands.executeCommand('editor.action.hideHover');
    }

    // Ctrl+F5: run on the U64
    ev('scene', { name: 'vsc_run' });
    vscode.commands.executeCommand('u64bbc.run');
    await sleep(12000);
    ev('scene', { name: 'vsc_key' });
    await tapKey('space');
    await sleep(3000);

}

async function debugScene(dir) {
    // the debugger: breakpoint, variables, stepping
    ev('scene', { name: 'vsc_debug' });
    const sq = path.join(dir, 'squares.bas');
    const sqDoc = await openFile(sq);
    await sleep(1500);
    vscode.debug.addBreakpoints([new vscode.SourceBreakpoint(
        new vscode.Location(sqDoc.uri, new vscode.Position(2, 0)))]);
    await sleep(1500);
    await vscode.commands.executeCommand('workbench.view.debug');
    await vscode.debug.startDebugging(undefined,
        { type: 'u64bbc', request: 'launch', name: 'Debug squares.bas', program: sq });
    await sleep(6000);
    for (let i = 0; i < 4; i++) {
        ev('step');
        await vscode.commands.executeCommand('workbench.action.debug.stepOver');
        await sleep(2500);
    }
    ev('continue');
    await vscode.commands.executeCommand('workbench.action.debug.continue');
    await sleep(5000);
    vscode.debug.removeBreakpoints(vscode.debug.breakpoints);
    if (vscode.debug.activeDebugSession) {
        await vscode.debug.stopDebugging();
    }
    await sleep(2000);
}
