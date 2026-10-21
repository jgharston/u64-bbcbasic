// Starts the scene (take.js) once VS Code is up, then quits VS Code.
// Loaded as a second development extension by tools/video/v1_vscode.py;
// a plain launch, not @vscode/test-electron, so the window keeps the size
// from the profile (a test window opens at a fixed 1448x904).
const vscode = require('vscode');
const take = require('./take');

exports.activate = function () {
    if (!process.env.U64_VIDEO_EVENTS) { return; }
    take.run()
        .catch(e => console.error('take failed:', e))
        .finally(() => vscode.commands.executeCommand('workbench.action.quit'));
};
exports.deactivate = function () {};
