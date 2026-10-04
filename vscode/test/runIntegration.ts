// Starts a real VS Code with this extension and runs test/suite/index.ts
// inside it:  U64_HOST=192.168.1.148 npm run test:vscode
import * as path from 'path';
import { runTests } from '@vscode/test-electron';

async function main() {
    const root = path.resolve(__dirname, '../..');
    await runTests({
        extensionDevelopmentPath: root,
        extensionTestsPath: path.resolve(__dirname, 'suite/index'),
        launchArgs: ['--disable-extensions', '--disable-gpu', path.resolve(root, 'test')],
    });
}

main().catch(e => { console.error(e); process.exit(1); });
