// A headless VT/xterm screen. Program output goes in as bytes; a snapshot of styled text runs comes
// out. It keeps a primary screen with scrollback and an alternate screen for full-screen programs,
// so a session's screen survives a restart of the world that draws it. Characters are one cell
// wide; wide CJK and emoji glyphs are not yet given two cells.

const palette = [
  '#1b2430', '#e06c75', '#7ec699', '#e5c07b', '#61afef', '#c678dd', '#56c8d8', '#c9d4df',
  '#4b5a6a', '#ff7a85', '#98e2b1', '#ffd88a', '#82c4ff', '#de9cf2', '#7ee8f5', '#ffffff',
];
for (let r = 0; r < 6; r++) for (let g = 0; g < 6; g++) for (let b = 0; b < 6; b++) {
  const level = value => (value ? 55 + value * 40 : 0).toString(16).padStart(2, '0');
  palette.push(`#${level(r)}${level(g)}${level(b)}`);
}
for (let gray = 0; gray < 24; gray++) {
  const value = (8 + gray * 10).toString(16).padStart(2, '0');
  palette.push(`#${value}${value}${value}`);
}

const plain = Object.freeze({ fg: null, bg: null, bold: false, dim: false, italic: false, underline: false, inverse: false, strike: false });
const hex = value => `#${Math.max(0, Math.min(255, value)).toString(16).padStart(2, '0')}`.slice(1);

export function createScreen({ cols = 120, rows = 32, scrollback = 2000 } = {}) {
  const styles = [plain];
  const styleIds = new Map([[JSON.stringify(plain), 0]]);
  const styleId = style => {
    const key = JSON.stringify(style);
    if (!styleIds.has(key)) { styleIds.set(key, styles.length); styles.push(Object.freeze({ ...style })); }
    return styleIds.get(key);
  };
  const blank = (style = 0) => ({ ch: ' ', style });
  const blankLine = (style = 0) => Array.from({ length: cols }, () => blank(style));

  let primary = Array.from({ length: rows }, () => blankLine());
  let alternate = null;
  let lines = primary;
  const history = [];
  let x = 0, y = 0, wrapPending = false;
  let saved = { x: 0, y: 0, attrs: { ...plain } };
  let savedPrimary = null;
  let attrs = { ...plain };
  let top = 0, bottom = rows - 1;
  const modes = { autowrap: true, cursor: true, appCursor: false, bracketedPaste: false, insert: false };
  let title = '';
  let version = 0;
  const replies = [];
  const decoder = new TextDecoder('utf-8');
  let state = 'ground', params = '', marker = '', intermediate = '', text = '';

  const current = () => styleId(attrs);
  const clampY = value => Math.max(0, Math.min(rows - 1, value));
  const clampX = value => Math.max(0, Math.min(cols - 1, value));

  function scrollUp(count = 1, from = top, to = bottom) {
    for (let index = 0; index < count; index++) {
      const removed = lines.splice(from, 1)[0];
      if (lines === primary && from === 0 && scrollback > 0) {
        history.push(removed);
        if (history.length > scrollback) history.shift();
      }
      lines.splice(to, 0, blankLine(current()));
    }
  }
  function scrollDown(count = 1, from = top, to = bottom) {
    for (let index = 0; index < count; index++) {
      lines.splice(to, 1);
      lines.splice(from, 0, blankLine(current()));
    }
  }
  function lineFeed() {
    wrapPending = false;
    if (y === bottom) scrollUp();
    else y = clampY(y + 1);
  }
  function print(ch) {
    if (wrapPending && modes.autowrap) { x = 0; lineFeed(); }
    wrapPending = false;
    const row = lines[y];
    if (modes.insert) { row.splice(x, 0, blank()); row.length = cols; }
    row[x] = { ch, style: current() };
    if (x === cols - 1) wrapPending = true;
    else x++;
  }
  function eraseLine(row, from, to) {
    const style = current();
    for (let column = from; column <= to; column++) lines[row][column] = blank(style);
  }
  function setAlternate(on, saveCursor) {
    if (on && !alternate) {
      if (saveCursor) savedPrimary = { x, y, attrs: { ...attrs } };
      alternate = Array.from({ length: rows }, () => blankLine());
      lines = alternate;
    } else if (!on && alternate) {
      alternate = null;
      lines = primary;
      if (saveCursor && savedPrimary) ({ x, y } = savedPrimary);
    }
    wrapPending = false;
  }
  function color(list, index) {
    // 38;5;n or 38;2;r;g;b, with the same forms for 48. Returns [color, consumed].
    if (list[index] === 5 && list[index + 1] !== undefined) return [palette[list[index + 1]] ?? null, 2];
    if (list[index] === 2 && list[index + 3] !== undefined) {
      return [`#${hex(list[index + 1])}${hex(list[index + 2])}${hex(list[index + 3])}`, 4];
    }
    return [null, 0];
  }
  function sgr(list) {
    if (!list.length) list = [0];
    for (let index = 0; index < list.length; index++) {
      const code = list[index];
      if (code === 0) attrs = { ...plain };
      else if (code === 1) attrs.bold = true;
      else if (code === 2) attrs.dim = true;
      else if (code === 3) attrs.italic = true;
      else if (code === 4) attrs.underline = true;
      else if (code === 7) attrs.inverse = true;
      else if (code === 9) attrs.strike = true;
      else if (code === 21 || code === 22) { attrs.bold = false; attrs.dim = false; }
      else if (code === 23) attrs.italic = false;
      else if (code === 24) attrs.underline = false;
      else if (code === 27) attrs.inverse = false;
      else if (code === 29) attrs.strike = false;
      else if (code >= 30 && code <= 37) attrs.fg = palette[code - 30];
      else if (code === 39) attrs.fg = null;
      else if (code >= 40 && code <= 47) attrs.bg = palette[code - 40];
      else if (code === 49) attrs.bg = null;
      else if (code >= 90 && code <= 97) attrs.fg = palette[code - 82];
      else if (code >= 100 && code <= 107) attrs.bg = palette[code - 92];
      else if (code === 38 || code === 48) {
        const [value, consumed] = color(list, index + 1);
        if (code === 38) attrs.fg = value; else attrs.bg = value;
        index += consumed;
      }
    }
  }
  function privateMode(list, on) {
    for (const mode of list) {
      if (mode === 1) modes.appCursor = on;
      else if (mode === 7) modes.autowrap = on;
      else if (mode === 25) modes.cursor = on;
      else if (mode === 2004) modes.bracketedPaste = on;
      else if (mode === 47 || mode === 1047) setAlternate(on, false);
      else if (mode === 1049) {
        if (on) { setAlternate(true, true); } else { setAlternate(false, true); }
      }
    }
  }
  function csi(final) {
    const list = params === '' ? [] : params.split(';').map(part => (part === '' ? 0 : Number.parseInt(part, 10) || 0));
    const n = Math.max(1, list[0] || 1);
    if (marker === '?') {
      if (final === 'h' || final === 'l') privateMode(list, final === 'h');
      return;
    }
    if (marker === '>' || marker === '=' || intermediate) return;
    switch (final) {
      case '@': { const row = lines[y]; row.splice(x, 0, ...Array.from({ length: Math.min(n, cols - x) }, () => blank(current()))); row.length = cols; break; }
      case 'A': y = Math.max(y < top ? 0 : top, y - n); break;
      case 'B': y = Math.min(y > bottom ? rows - 1 : bottom, y + n); break;
      case 'C': x = clampX(x + n); break;
      case 'D': x = clampX(x - n); break;
      case 'E': x = 0; y = clampY(y + n); break;
      case 'F': x = 0; y = clampY(y - n); break;
      case 'G': case '`': x = clampX(n - 1); break;
      case 'H': case 'f': y = clampY((list[0] || 1) - 1); x = clampX((list[1] || 1) - 1); break;
      case 'J': {
        const mode = list[0] || 0;
        if (mode === 0) { eraseLine(y, x, cols - 1); for (let row = y + 1; row < rows; row++) eraseLine(row, 0, cols - 1); }
        else if (mode === 1) { eraseLine(y, 0, x); for (let row = 0; row < y; row++) eraseLine(row, 0, cols - 1); }
        else if (mode === 2) { for (let row = 0; row < rows; row++) eraseLine(row, 0, cols - 1); }
        else if (mode === 3 && lines === primary) history.length = 0;
        break;
      }
      case 'K': {
        const mode = list[0] || 0;
        if (mode === 0) eraseLine(y, x, cols - 1); else if (mode === 1) eraseLine(y, 0, x); else eraseLine(y, 0, cols - 1);
        break;
      }
      case 'L': if (y >= top && y <= bottom) scrollDown(Math.min(n, bottom - y + 1), y, bottom); break;
      case 'M': if (y >= top && y <= bottom) scrollUp(Math.min(n, bottom - y + 1), y, bottom); break;
      case 'P': { const row = lines[y]; row.splice(x, Math.min(n, cols - x)); while (row.length < cols) row.push(blank(current())); break; }
      case 'S': scrollUp(n); break;
      case 'T': scrollDown(n); break;
      case 'X': eraseLine(y, x, Math.min(cols - 1, x + n - 1)); break;
      case 'd': y = clampY(n - 1); break;
      case 'm': sgr(list); break;
      case 'r': {
        const first = (list[0] || 1) - 1, last = (list[1] || rows) - 1;
        if (first < last && last < rows) { top = first; bottom = last; x = 0; y = 0; }
        break;
      }
      case 's': saved = { x, y, attrs: { ...attrs } }; break;
      case 'u': ({ x, y } = saved); attrs = { ...saved.attrs }; break;
      case 'n':
        if (list[0] === 5) replies.push('\x1b[0n');
        else if (list[0] === 6) replies.push(`\x1b[${y + 1};${x + 1}R`);
        break;
      case 'c': if (!list[0]) replies.push('\x1b[?1;2c'); break;
      case 'h': case 'l': if (list.includes(4)) modes.insert = final === 'h'; break;
      default: break;
    }
    if (final !== 'm') wrapPending = false;
  }
  function escape(ch) {
    switch (ch) {
      case '[': state = 'csi'; params = ''; marker = ''; intermediate = ''; return;
      case ']': state = 'osc'; text = ''; return;
      case 'P': case 'X': case '^': case '_': state = 'string'; return;
      case '(': case ')': case '*': case '+': state = 'charset'; return;
      case '7': saved = { x, y, attrs: { ...attrs } }; break;
      case '8': ({ x, y } = saved); attrs = { ...saved.attrs }; break;
      case 'D': lineFeed(); break;
      case 'E': x = 0; lineFeed(); break;
      case 'M': if (y === top) scrollDown(); else y = clampY(y - 1); break;
      case 'c': reset(); break;
      default: break;
    }
    state = 'ground';
  }
  function reset() {
    primary = Array.from({ length: rows }, () => blankLine());
    alternate = null; lines = primary; history.length = 0;
    x = 0; y = 0; wrapPending = false; attrs = { ...plain }; top = 0; bottom = rows - 1;
    Object.assign(modes, { autowrap: true, cursor: true, appCursor: false, bracketedPaste: false, insert: false });
  }
  function feed(ch) {
    const code = ch.codePointAt(0);
    if (state === 'osc') {
      if (ch === '\x07') { finishOsc(); state = 'ground'; }
      else if (ch === '\x1b') state = 'osc-escape';
      else if (text.length < 4096) text += ch;
      return;
    }
    if (state === 'osc-escape') { finishOsc(); state = 'ground'; return; }
    if (state === 'string') { if (ch === '\x1b') state = 'string-escape'; else if (ch === '\x07') state = 'ground'; return; }
    if (state === 'string-escape') { state = 'ground'; return; }
    if (state === 'charset') { state = 'ground'; return; }
    if (code === 0x1b) { state = 'escape'; return; }
    if (code < 0x20 || code === 0x7f) { control(code); return; }
    if (state === 'escape') { escape(ch); return; }
    if (state === 'csi') {
      if (ch >= '0' && ch <= '9' || ch === ';' || ch === ':') params += ch === ':' ? ';' : ch;
      else if ('?>=<'.includes(ch) && params === '') marker = ch;
      else if (ch >= ' ' && ch <= '/') intermediate += ch;
      else { state = 'ground'; csi(ch); }
      return;
    }
    print(ch);
  }
  function finishOsc() {
    const split = text.indexOf(';');
    const kind = split < 0 ? text : text.slice(0, split);
    if (kind === '0' || kind === '2') title = text.slice(split + 1).slice(0, 200);
  }
  function control(code) {
    switch (code) {
      case 0x08: if (x > 0) x--; wrapPending = false; break;
      case 0x09: x = Math.min(cols - 1, (Math.floor(x / 8) + 1) * 8); break;
      case 0x0a: case 0x0b: case 0x0c: lineFeed(); break;
      case 0x0d: x = 0; wrapPending = false; break;
      default: break;
    }
  }

  return {
    write(chunk) {
      const input = typeof chunk === 'string' ? chunk : decoder.decode(chunk, { stream: true });
      for (const ch of input) feed(ch);
      version++;
    },
    resize(nextCols, nextRows) {
      nextCols = Math.max(10, Math.min(400, Math.floor(nextCols)));
      nextRows = Math.max(4, Math.min(200, Math.floor(nextRows)));
      if (nextCols === cols && nextRows === rows) return;
      const fit = buffer => {
        for (const row of buffer) {
          if (row.length > nextCols) row.length = nextCols;
          while (row.length < nextCols) row.push(blank());
        }
      };
      cols = nextCols;
      for (const buffer of [primary, alternate].filter(Boolean)) {
        fit(buffer);
        while (buffer.length > nextRows) {
          // Keep the cursor's line on screen: drop lines from the top into history first.
          const removed = buffer.shift();
          if (buffer === primary && y > 0) { history.push(removed); if (history.length > scrollback) history.shift(); }
          if (buffer === lines) y = Math.max(0, y - 1);
        }
        while (buffer.length < nextRows) buffer.push(blankLine());
      }
      fit(history);
      rows = nextRows; top = 0; bottom = rows - 1;
      x = clampX(x); y = clampY(y); wrapPending = false;
      version++;
    },
    // offset scrolls the primary screen back into history, in lines.
    snapshot(offset = 0) {
      const back = lines === primary ? Math.max(0, Math.min(history.length, Math.floor(offset))) : 0;
      const source = back ? [...history.slice(history.length - back), ...lines].slice(0, rows) : lines;
      const used = new Map();
      const runs = source.map(row => {
        let end = row.length;
        while (end > 0 && row[end - 1].ch === ' ' && row[end - 1].style === 0) end--;
        const out = [];
        for (let index = 0; index < end; index++) {
          const cell = row[index];
          if (!used.has(cell.style)) used.set(cell.style, used.size);
          const local = used.get(cell.style);
          if (out.length && out[out.length - 1][1] === local) out[out.length - 1][0] += cell.ch;
          else out.push([cell.ch, local]);
        }
        return out;
      });
      return {
        version, cols, rows, title, lines: runs,
        styles: [...used.keys()].map(id => styles[id]),
        cursor: { x, y: y + back, visible: modes.cursor && back === 0 },
        alternate: lines !== primary, history: history.length, offset: back,
        modes: { app_cursor: modes.appCursor, bracketed_paste: modes.bracketedPaste },
      };
    },
    // Answers the program asked for, such as a cursor position report. Send them back as input.
    takeReplies() { return replies.splice(0); },
    get version() { return version; },
    get size() { return { cols, rows }; },
  };
}
