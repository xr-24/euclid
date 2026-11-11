import assert from 'node:assert/strict';
import test from 'node:test';
import { createScreen } from './screen.mjs';

const text = screen => screen.snapshot().lines.map(line => line.map(run => run[0]).join(''));
const style = (screen, row, run = 0) => {
  const snap = screen.snapshot();
  return snap.styles[snap.lines[row][run][1]];
};

test('printing wraps at the right edge and scrolls finished lines into history', () => {
  const screen = createScreen({ cols: 5, rows: 3 });
  screen.write('abcdefgh\r\nline3\r\nline4');
  assert.deepEqual(text(screen), ['fgh', 'line3', 'line4']);
  assert.equal(screen.snapshot().history, 1);
  assert.deepEqual(screen.snapshot(1).lines.map(line => line.map(run => run[0]).join('')), ['abcde', 'fgh', 'line3']);
  assert.equal(screen.snapshot(1).cursor.visible, false, 'the cursor hides while scrolled back');
  // A full last column waits for the next character before wrapping.
  const edge = createScreen({ cols: 3, rows: 2 });
  edge.write('abc\r\nx');
  assert.deepEqual(text(edge), ['abc', 'x']);
});

test('cursor addressing, erasing, tabs and backspace edit the grid in place', () => {
  const screen = createScreen({ cols: 10, rows: 4 });
  screen.write('0123456789\r\nabcdefghij');
  screen.write('\x1b[1;4HX\x1b[2;3H\x1b[K');
  assert.deepEqual(text(screen).slice(0, 2), ['012X456789', 'ab']);
  screen.write('\x1b[1;6H\x1b[1K');
  assert.deepEqual(text(screen)[0], '      6789');
  screen.write('\x1b[2J\x1b[H\tA\x08B');
  assert.deepEqual(text(screen), ['        B', '', '', '']);
  screen.write('\x1b[3;2Hhello\x1b[2D\x1b[2Pz');
  assert.deepEqual(text(screen)[2], ' helz');
  screen.write('\x1b[3;1H\x1b[2@');
  assert.deepEqual(text(screen)[2], '   helz');
  assert.deepEqual(screen.snapshot().cursor, { x: 0, y: 2, visible: true });
});

test('the alternate screen hides the shell and gives it back unchanged', () => {
  const screen = createScreen({ cols: 8, rows: 3 });
  screen.write('prompt> ');
  screen.write('\x1b[?1049h\x1b[2J\x1b[Hfull\r\nscreen');
  assert.equal(screen.snapshot().alternate, true);
  assert.deepEqual(text(screen), ['full', 'screen', '']);
  screen.write('\x1b[?1049l');
  assert.equal(screen.snapshot().alternate, false);
  assert.deepEqual(text(screen), ['prompt>', '', '']);
  assert.deepEqual(screen.snapshot().cursor, { x: 7, y: 0, visible: true });
  assert.equal(screen.snapshot().history, 0, 'full-screen output never reaches the shell history');
});

test('scroll regions, line insertion and reverse index keep the rest of the screen still', () => {
  const screen = createScreen({ cols: 6, rows: 5 });
  screen.write('head\r\na\r\nb\r\nc\r\nfoot');
  screen.write('\x1b[2;4r\x1b[4;1H\n');
  assert.deepEqual(text(screen), ['head', 'b', 'c', '', 'foot']);
  screen.write('\x1b[2;1H\x1b[L');
  assert.deepEqual(text(screen), ['head', '', 'b', 'c', 'foot']);
  screen.write('\x1b[2;1H\x1b[M');
  assert.deepEqual(text(screen), ['head', 'b', 'c', '', 'foot']);
  screen.write('\x1b[2;1H\x1bM');
  assert.deepEqual(text(screen), ['head', '', 'b', 'c', 'foot']);
  assert.equal(screen.snapshot().history, 0, 'a scroll region never feeds history');
});

test('colors and attributes become shared styles', () => {
  const screen = createScreen({ cols: 20, rows: 2 });
  screen.write('\x1b[1;31mred\x1b[22;38;5;45mcyan\x1b[38;2;10;20;30;48;5;0mrgb\x1b[0m plain\x1b[7m inv');
  assert.deepEqual(screen.snapshot().lines[0].map(run => run[0]), ['red', 'cyan', 'rgb', ' plain', ' inv']);
  assert.deepEqual([style(screen, 0, 0).fg, style(screen, 0, 0).bold], ['#e06c75', true]);
  assert.deepEqual([style(screen, 0, 1).fg, style(screen, 0, 1).bold], ['#00d7ff', false]);
  assert.deepEqual([style(screen, 0, 2).fg, style(screen, 0, 2).bg], ['#0a141e', '#1b2430']);
  assert.equal(style(screen, 0, 3).fg, null);
  assert.equal(style(screen, 0, 4).inverse, true);
  assert.equal(screen.snapshot().styles.length, 5, 'only styles in view are sent');
});

test('reports, titles, modes and UTF-8 split across chunks', () => {
  const screen = createScreen({ cols: 10, rows: 3 });
  screen.write('ab\x1b[6n\x1b[5n');
  assert.deepEqual(screen.takeReplies(), ['\x1b[1;3R', '\x1b[0n']);
  assert.deepEqual(screen.takeReplies(), []);
  screen.write('\x1b]0;Codex\x07\x1b[?25l\x1b[?1h\x1b[?2004h');
  const snap = screen.snapshot();
  assert.deepEqual([snap.title, snap.cursor.visible, snap.modes.app_cursor, snap.modes.bracketed_paste], ['Codex', false, true, true]);
  const bytes = Buffer.from('é→✓');
  screen.write(bytes.subarray(0, 1));
  screen.write(bytes.subarray(1, 4));
  screen.write(bytes.subarray(4));
  assert.equal(text(screen)[0], 'abé→✓');
  screen.write('\x1bc');
  assert.deepEqual([text(screen)[0], screen.snapshot().title], ['', 'Codex']);
});

test('resizing keeps the cursor line in view and the version moves with every change', () => {
  const screen = createScreen({ cols: 12, rows: 6 });
  screen.write('one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix');
  const before = screen.version;
  screen.resize(10, 4);
  assert.deepEqual(text(screen), ['three', 'four', 'five', 'six']);
  assert.deepEqual(screen.size, { cols: 10, rows: 4 });
  assert.equal(screen.snapshot().cursor.y, 3);
  assert.equal(screen.snapshot().history, 2, 'lines pushed off the top stay in history');
  assert.ok(screen.version > before);
  screen.resize(14, 7);
  assert.equal(text(screen).length, 7);
  screen.resize(2, 1);
  assert.deepEqual(screen.size, { cols: 10, rows: 4 }, 'sizes are clamped to a usable minimum');
});
