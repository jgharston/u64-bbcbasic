// Run the extension's remote code against a real machine:
//   U64_HOST=192.168.1.148 npm run test:device
import { Remote } from '../src/remote';

async function main() {
    const host = process.env.U64_HOST;
    if (!host) { console.error('set U64_HOST'); process.exit(3); }
    const r = new Remote(host, process.env.ULTIMATE_PASSWORD);
    const check = (name: string, ok: boolean, detail: unknown) => {
        console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}`);
        if (!ok) { console.log(JSON.stringify(detail, null, 1)); process.exitCode = 1; }
    };
    let res = await r.runLines(['PRINT 6*7']);
    check('exec', res.output === '        42\n', res);
    res = await r.sendProgram('10 FOR I%=1 TO 3\n20 PRINT "LINE ";I%\n30 NEXT\n40 PRINT 1/0\n', true);
    check('run with error', res.output.startsWith('LINE 1\nLINE 2\nLINE 3\n') &&
          JSON.stringify(res.error) === JSON.stringify({ number: 18, message: 'Division by zero', line: 40 }), res);
    res = await r.sendProgram('10 INPUT "NAME";N$\n20 PRINT "HI ";N$\n', true);
    check('input wanted', res.state === 'input', res);
    res = await r.runLines(['VSCODE']);
    check('input answered', res.output === 'HI VSCODE\n', res);
    const listed = await r.programText();
    check('program text', listed.startsWith('10 INPUT "NAME";N$'), listed);
    const screen = await r.screen();
    check('screen', screen.some(l => l.includes('HI VSCODE')), screen);
}

main().catch(e => { console.error(e); process.exit(3); });
