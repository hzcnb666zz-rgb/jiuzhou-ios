const net = require('node:net');
const fs = require('node:fs');
const path = require('node:path');
const { StringDecoder } = require('node:string_decoder');

const host = process.env.MUD_HOST || '127.0.0.1';
const port = Number(process.env.MUD_PORT || 6666);
const socket = net.createConnection({ host, port });
const decoder = new StringDecoder('utf8');
const chunks = [];
const account = 'iost' + Date.now().toString(36);
const alphabet = '青云山海松风明月清泉剑雨竹江雪天';
const name = '试' + Array.from({ length: 3 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join('');
let buffer = '';
let handshake = false;
let authenticated = false;
let created = false;
let entered = false;
let initialRoom = false;
let inspected = false;
let menu = false;
let inspectOffset = 0;
let moveOffset = 0;
let moved = false;
let complete = false;
const send = command => socket.write(command + '\n');
const timer = setTimeout(() => fail('Server test timed out.'), 30000);

function fail(message) {
  if (complete) return;
  complete = true;
  clearTimeout(timer);
  console.error(message);
  console.error(JSON.stringify({ handshake, authenticated, created, entered, initialRoom, inspected, menu, moved }));
  console.error(buffer.split('\n').filter(line => !line.startsWith('\x1b012')).join('\n').slice(-6500));
  socket.destroy();
  process.exitCode = 1;
}

socket.on('error', error => fail(error.message));
socket.on('data', data => {
  chunks.push(data);
  buffer += decoder.write(data);
  if (!handshake && buffer.includes('ver1.0,')) { handshake = true; send('local'); }
  if (!authenticated && buffer.includes('版本验证成功')) {
    authenticated = true;
    send(account + '║localtest║123456789abcd║local@localhost');
  }
  if (!created && buffer.includes('\x1b0000008')) { created = true; send('男性║║' + name); }
  if (!entered && buffer.includes('\x1b0000007')) {
    entered = true;
    setTimeout(() => { if (!complete) send('look'); }, 1500);
  }
  const clean = buffer.replace(/\x1b\[[0-9;]*m/g, '').replace(/\x1b\[[us]:[^\]]*\]/g, '');
  initialRoom ||= clean.includes('\x1b002未明谷');
  const npc = clean.match(/老村长:([^\r\n$]+)/);
  if (entered && npc && !inspected) { inspected = true; inspectOffset = buffer.length; send(npc[1]); }
  if (inspected && !menu && buffer.slice(inspectOffset).includes('\x1b008')) {
    menu = true; moveOffset = buffer.length; send('zs');
  }
  const titles = [...clean.matchAll(/\x1b002([^\r\n\x1b]+)/g)].map(match => match[1]);
  moved = menu && buffer.slice(moveOffset).includes('\x1b002') && titles.some(title => title.includes('洗心池'));
  if (entered && initialRoom && menu && moved && !complete) {
    complete = true;
    clearTimeout(timer);
    const dir = path.resolve(__dirname, '../Tests/Fixtures');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'local-session.bin'), Buffer.concat(chunks));
    send('quit');
    socket.end();
    console.log(JSON.stringify({ handshake, created, entered, initialRoom, menu, moved, titles, fixtureBytes: Buffer.concat(chunks).length }, null, 2));
    setTimeout(() => socket.destroy(), 500);
  }
});
socket.on('close', () => { if (!complete) fail('Server closed before the test completed.'); });
