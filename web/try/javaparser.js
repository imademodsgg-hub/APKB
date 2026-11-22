/* APKB Try Before Build — Java lexer + parser (Java 8 + common Java 11/14 syntax). Reports exact file:line:col errors. */
(function (G) {
const APKB = G.APKB = G.APKB || {};
class ParseError extends Error { constructor(msg, file, line, col) { super(msg); this.file = file; this.line = line; this.col = col; } }
const KW = new Set('abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null'.split(' '));
const PRIM = new Set(['int', 'long', 'short', 'byte', 'char', 'float', 'double', 'boolean', 'void']);
const MODS = new Set(['public', 'private', 'protected', 'static', 'final', 'abstract', 'native', 'synchronized', 'transient', 'volatile', 'strictfp', 'default']);
const OPS = ['>>>=', '<<=', '>>=', '>>>', '...', '->', '::', '++', '--', '&&', '||', '==', '!=', '<=', '>=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>', '+', '-', '*', '/', '%', '&', '|', '^', '!', '~', '?', ':', ';', ',', '.', '(', ')', '[', ']', '{', '}', '<', '>', '=', '@'];
function lex(src, file) {
  const T = []; let i = 0, line = 1, ls = 0; const n = src.length;
  const err = (m, l = line, c = i - ls + 1) => { throw new ParseError(m, file, l, c); };
  const esc = () => { const c = src[++i]; i++; switch (c) { case 'n': return '\n'; case 't': return '\t'; case 'r': return '\r'; case 'b': return '\b'; case 'f': return '\f'; case 's': return ' '; case '0': return '\0'; case '\\': return '\\'; case '"': return '"'; case "'": return "'"; case 'u': { while (src[i] === 'u') i++; const h = src.substr(i, 4); i += 4; return String.fromCharCode(parseInt(h, 16)); } default: if (c >= '0' && c <= '7') { let o = c; while (src[i] >= '0' && src[i] <= '7' && o.length < 3) o += src[i++]; return String.fromCharCode(parseInt(o, 8)); } err('illegal escape character \\' + c); } };
  while (i < n) {
    const c = src[i];
    if (c === '\n') { line++; i++; ls = i; continue; }
    if (c === ' ' || c === '\t' || c === '\r' || c === '\f') { i++; continue; }
    if (c === '/' && src[i + 1] === '/') { while (i < n && src[i] !== '\n') i++; continue; }
    if (c === '/' && src[i + 1] === '*') { const sl = line, sc = i - ls + 1; i += 2; while (i < n && !(src[i] === '*' && src[i + 1] === '/')) { if (src[i] === '\n') { line++; ls = i + 1; } i++; } if (i >= n) err('unterminated comment', sl, sc); i += 2; continue; }
    const col = i - ls + 1, tl = line;
    if (/[A-Za-z_$\u0080-\uffff]/.test(c)) { let j = i + 1; while (j < n && /[\w$\u0080-\uffff]/.test(src[j])) j++; const w = src.slice(i, j); i = j; T.push({ t: KW.has(w) ? 'kw' : 'id', v: w, line: tl, col }); continue; }
    if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(src[i + 1] || ''))) {
      let j = i, kind = 'int', v;
      if (c === '0' && /[xX]/.test(src[i + 1] || '')) { j += 2; while (/[0-9a-fA-F_]/.test(src[j] || '')) j++; v = parseInt(src.slice(i + 2, j).replace(/_/g, ''), 16); if (/[lL]/.test(src[j] || '')) { kind = 'long'; j++; } else v = v | 0; }
      else if (c === '0' && /[bB]/.test(src[i + 1] || '')) { j += 2; while (/[01_]/.test(src[j] || '')) j++; v = parseInt(src.slice(i + 2, j).replace(/_/g, ''), 2); if (/[lL]/.test(src[j] || '')) { kind = 'long'; j++; } }
      else {
        while (/[0-9_]/.test(src[j] || '')) j++; let fl = false;
        if (src[j] === '.' && /[0-9]/.test(src[j + 1] || '')) { fl = true; j++; while (/[0-9_]/.test(src[j] || '')) j++; } else if (src[j] === '.' && !/[A-Za-z_.]/.test(src[j + 1] || '')) { fl = true; j++; }
        if (/[eE]/.test(src[j] || '') && /[-+0-9]/.test(src[j + 1] || '')) { fl = true; j += 2; while (/[0-9]/.test(src[j] || '')) j++; }
        const txt = src.slice(i, j).replace(/_/g, ''); v = fl ? parseFloat(txt) : (txt.length > 1 && txt[0] === '0' ? parseInt(txt, 8) : parseInt(txt, 10)); kind = fl ? 'double' : 'int';
        const s = src[j]; if (s === 'L' || s === 'l') { kind = 'long'; j++; } else if (s === 'f' || s === 'F') { kind = 'float'; j++; } else if (s === 'd' || s === 'D') { kind = 'double'; j++; }
      }
      i = j; T.push({ t: 'num', v, kind, line: tl, col }); continue;
    }
    if (c === '"') {
      if (src.startsWith('"""', i)) { i += 3; while (src[i] !== '\n' && i < n) i++; i++; line++; ls = i; let s = ''; while (i < n && !src.startsWith('"""', i)) { if (src[i] === '\\') s += esc(); else { if (src[i] === '\n') { line++; ls = i + 1; } s += src[i++]; } } if (i >= n) err('unterminated text block', tl, col); i += 3; const lines = s.split('\n'), ind = Math.min(...lines.filter(l => l.trim()).map(l => l.match(/^ */)[0].length), 1e9); T.push({ t: 'str', v: lines.map(l => l.slice(ind === 1e9 ? 0 : ind)).join('\n'), line: tl, col }); continue; }
      i++; let s = ''; while (i < n && src[i] !== '"') { if (src[i] === '\n') err('unclosed string literal', tl, col); s += src[i] === '\\' ? esc() : src[i++]; } if (i >= n) err('unclosed string literal', tl, col); i++; T.push({ t: 'str', v: s, line: tl, col }); continue;
    }
    if (c === "'") { i++; let s = src[i] === '\\' ? esc() : src[i++]; if (src[i] !== "'") err('unclosed character literal', tl, col); i++; T.push({ t: 'chr', v: s.charCodeAt(0), line: tl, col }); continue; }
    let op = null; for (const o of OPS) if (src.startsWith(o, i)) { op = o; break; }
    if (!op) err("illegal character: '" + c + "'");
    i += op.length; T.push({ t: 'op', v: op, line: tl, col });
  }
  T.push({ t: 'eof', v: '<end of file>', line, col: i - ls + 1 }); return T;
}
class Fail extends Error {}
function parse(src, file) {
  const T = lex(src, file); let p = 0;
  const tk = () => T[p], pk = k => T[Math.min(p + k, T.length - 1)];
  const err = (m, t = tk()) => { throw new ParseError(m, file, t.line, t.col); };
  const is = (v, t = tk()) => (t.t === 'op' || t.t === 'kw') && t.v === v;
  const isId = (t = tk()) => t.t === 'id';
  const accept = v => { if (is(v)) { p++; return true; } return false; };
  const expect = v => { if (!accept(v)) { const t = tk(), prev = T[p - 1] || t; err(`'${v}' expected` + (t.t === 'eof' ? '' : `, found '${t.v}'`), v === ';' || v === ')' || v === ']' ? (prev.line < t.line ? prev : t) : t); } };
  const ident = () => { const t = tk(); if (t.t !== 'id') { err(`<identifier> expected, found '${t.v}'`); } p++; return t.v; };
  const spec = f => { const s = p; try { return f(); } catch (e) { if (e instanceof ParseError || e instanceof Fail) { p = s; return null; } throw e; } };
  function skipAnn() { while (is('@') && !is('interface', pk(1))) { p++; ident(); while (accept('.')) ident(); if (is('(')) { let d = 0; do { if (is('(')) d++; else if (is(')')) d--; p++; } while (d > 0 && tk().t !== 'eof'); } } }
  function mods() { const m = {}; for (; ;) { skipAnn(); const t = tk(); if (t.t === 'kw' && MODS.has(t.v) && !(t.v === 'default' && (is(':', pk(1)) || is('->', pk(1))))) { m[t.v] = true; p++; } else if (t.t === 'id' && (t.v === 'sealed' || t.v === 'non') && 0) p++; else break; } return m; }
  function typeArgs() { if (!is('<')) return; let d = 0; for (; ;) { const t = tk(); if (t.t === 'op') { if (t.v === '<') d++; else if (t.v === '>') d--; else if (t.v === '>>') d -= 2; else if (t.v === '>>>') d -= 3; else if (![',', '.', '?', '[', ']', '&', '@'].includes(t.v)) throw new Fail(); } else if (t.t === 'kw') { if (!PRIM.has(t.v) && !['extends', 'super'].includes(t.v)) throw new Fail(); } else if (t.t !== 'id') throw new Fail(); p++; if (d <= 0) break; } }
  function type() { const t = tk(); let n; if (t.t === 'kw' && PRIM.has(t.v)) { n = t.v; p++; } else if (t.t === 'id') { n = t.v; p++; typeArgs(); while (is('.') && isId(pk(1))) { p++; n = tk().v; p++; typeArgs(); } } else throw new Fail(); let d = 0; while (is('[') && is(']', pk(1))) { p += 2; d++; } return { n, d }; }
  const ptype = () => { const r = spec(type); if (!r) err(`<identifier> expected, found '${tk().v}'`); return r; };
  function isLocalDecl() { const s = p; try { skipAnn(); while (is('final')) p++; const r = type(); const t = tk(), nx = pk(1); const ok = t.t === 'id' && nx.t === 'op' && ['=', ';', ',', ':', '['].includes(nx.v); return ok; } catch (e) { if (e instanceof Fail || e instanceof ParseError) return false; throw e; } finally { p = s; } }

  // ---------------------------------------------------------------- declarations
  function compilationUnit() { const cu = { pkg: '', imports: [], types: [], file }; skipAnn(); if (accept('package')) { cu.pkg = qname(); expect(';'); } while (is('import')) { p++; accept('static'); let q = ident(); while (accept('.')) q += '.' + (accept('*') ? '*' : ident()); expect(';'); cu.imports.push(q); } while (tk().t !== 'eof') { if (accept(';')) continue; const m = mods(); cu.types.push(typeDecl(m)); } return cu; }
  const qname = () => { let q = ident(); while (is('.') && isId(pk(1))) { p++; q += '.' + ident(); } return q; };
  function typeDecl(m) {
    const t = tk(), line = t.line; let k;
    if (accept('class')) k = 'class'; else if (accept('interface')) k = 'interface'; else if (accept('enum')) k = 'enum'; else if (is('@') && is('interface', pk(1))) { p += 2; k = 'interface'; } else err("class, interface, or enum expected");
    const d = { k, name: ident(), sup: null, ifaces: [], members: [], mods: m, line, file, consts: [] };
    if (is('<')) { try { typeArgs(); } catch (e) { err('invalid type parameters'); } }
    if (accept('extends')) { if (k === 'interface') { do { d.ifaces.push(qtype()); } while (accept(',')); } else d.sup = qtype(); }
    if (accept('implements')) do { d.ifaces.push(qtype()); } while (accept(','));
    if (isId() && tk().v === 'permits') { p++; do { qtype(); } while (accept(',')); }
    classBody(d); return d;
  }
  const qtype = () => { const t = type(); return t.n; };
  function classBody(d) {
    expect('{');
    if (d.k === 'enum') {
      while (!is(';') && !is('}')) { skipAnn(); const line = tk().line, name = ident(); let args = [], body = null; if (is('(')) args = arguments_(); if (is('{')) { body = { k: 'class', name: d.name + '$' + name, sup: d.name, ifaces: [], members: [], mods: {}, line, file, consts: [], anon: true }; classBody(body); } d.consts.push({ name, args, body, line }); if (!accept(',')) break; }
      accept(';');
    }
    while (!is('}')) { if (tk().t === 'eof') err("reached end of file while parsing"); member(d); }
    expect('}');
  }
  function params() { expect('('); const ps = []; if (!is(')')) do { mods(); const ty = ptype(); let va = false; if (accept('...')) { va = true; ty.d++; } const nm = ident(); while (is('[')) { p += 2; ty.d++; } ps.push({ name: nm, type: ty, varargs: va }); } while (accept(',')); expect(')'); return ps; }
  function member(d) {
    if (accept(';')) return; const line = tk().line; const m = mods();
    if (is('class') || is('interface') || is('enum') || (is('@') && is('interface', pk(1)))) { d.members.push({ m: 'class', decl: typeDecl(m), line }); return; }
    if (is('{')) { d.members.push({ m: 'init', static: !!m.static, body: block(), line }); return; }
    if (is('<')) { try { typeArgs(); } catch (e) { err('invalid type parameters'); } }
    if (isId() && tk().v === d.name && is('(', pk(1))) { p++; const ps = params(); if (accept('throws')) do { qtype(); } while (accept(',')); d.members.push({ m: 'ctor', params: ps, body: block(), line }); return; }
    if (isId() && is('(', pk(1))) err('invalid method declaration; return type required');
    const ty = ptype(); const nline = tk().line, name = ident();
    if (is('(')) { const ps = params(); while (is('[')) { p += 2; ty.d++; } if (accept('throws')) do { qtype(); } while (accept(',')); let body = null; if (is('{')) body = block(); else { if (accept('default')) { expr(); } expect(';'); } d.members.push({ m: 'method', name, params: ps, ret: ty, body, static: !!m.static, abs: !body, line: nline, mods: m }); return; }
    let nm = name; for (; ;) { const t2 = { n: ty.n, d: ty.d }; while (is('[')) { p += 2; t2.d++; } let init = null; if (accept('=')) init = is('{') ? arrInit() : expr(); d.members.push({ m: 'field', type: t2, name: nm, init, static: !!m.static || d.k === 'interface', line: nline, final: !!m.final }); if (accept(',')) { nm = ident(); continue; } break; }
    expect(';');
  }
  // ---------------------------------------------------------------- statements
  function block() { const line = tk().line; expect('{'); const body = []; while (!is('}')) { if (tk().t === 'eof') err('reached end of file while parsing'); body.push(stmt()); } p++; return { t: 'Block', body, line }; }
  function localDecl(inFor) { const line = tk().line; mods(); const ty = ptype(); const decls = []; do { const name = ident(); let d = 0; while (is('[')) { p += 2; d++; } let init = null; if (accept('=')) init = is('{') ? arrInit() : expr(); decls.push({ name, d, init }); } while (accept(',')); if (!inFor) expect(';'); return { t: 'Local', type: ty, decls, line }; }
  function stmt() {
    const t = tk(), line = t.line;
    if (t.t === 'op') { if (t.v === '{') return block(); if (t.v === ';') { p++; return { t: 'Empty', line }; } if (t.v === '@') { skipAnn(); return stmt(); } }
    if (t.t === 'id' && is(':', pk(1)) && !is(':', pk(2))) { p += 2; return { t: 'Labeled', label: t.v, s: stmt(), line }; }
    if (t.t === 'id' && t.v === 'yield' && !is('=', pk(1)) && !is('.', pk(1)) && !is('(', pk(1))) { p++; const e = expr(); expect(';'); return { t: 'Yield', e, line }; }
    if (t.t === 'kw') switch (t.v) {
      case 'if': { p++; expect('('); const c = expr(); expect(')'); const a = stmt(); let b = null; if (accept('else')) b = stmt(); return { t: 'If', c, a, b, line }; }
      case 'while': { p++; expect('('); const c = expr(); expect(')'); return { t: 'While', c, body: stmt(), line }; }
      case 'do': { p++; const body = stmt(); expect('while'); expect('('); const c = expr(); expect(')'); expect(';'); return { t: 'Do', c, body, line }; }
      case 'for': { p++; expect('(');
        if (isLocalDecl()) { const s = p; mods(); const ty = ptype(); if (isId() && is(':', pk(1))) { const name = ident(); p++; const iter = expr(); expect(')'); return { t: 'ForEach', type: ty, name, iter, body: stmt(), line }; } p = s; }
        const init = []; if (!is(';')) { if (isLocalDecl()) init.push(localDecl(true)); else do { init.push({ t: 'ExprS', e: expr(), line }); } while (accept(',')); } expect(';');
        const c = is(';') ? null : expr(); expect(';'); const upd = []; if (!is(')')) do { upd.push(expr()); } while (accept(',')); expect(')'); return { t: 'For', init, c, upd, body: stmt(), line }; }
      case 'return': { p++; let e = null; if (!is(';')) e = expr(); expect(';'); return { t: 'Return', e, line }; }
      case 'break': { p++; let label = null; if (isId()) label = ident(); expect(';'); return { t: 'Break', label, line }; }
      case 'continue': { p++; let label = null; if (isId()) label = ident(); expect(';'); return { t: 'Continue', label, line }; }
      case 'throw': { p++; const e = expr(); expect(';'); return { t: 'Throw', e, line }; }
      case 'try': { p++; const res = []; if (accept('(')) { while (!is(')')) { if (isLocalDecl()) { const l = localDecl(true); res.push(l); } else res.push({ t: 'ExprS', e: expr(), line }); if (!accept(';')) break; } expect(')'); } const body = block(); const catches = []; while (is('catch')) { p++; expect('('); mods(); const types = [qtype()]; while (accept('|')) types.push(qtype()); const name = ident(); expect(')'); catches.push({ types, name, body: block() }); } let fin = null; if (accept('finally')) fin = block(); if (!catches.length && !fin && !res.length) err("'try' without 'catch', 'finally' or resource declarations", t); return { t: 'Try', res, body, catches, fin, line }; }
      case 'switch': { const s = switchBody(false); return s; }
      case 'synchronized': { p++; expect('('); const e = expr(); expect(')'); return { t: 'Sync', e, body: block(), line }; }
      case 'assert': { p++; const c = expr(); let m = null; if (accept(':')) m = expr(); expect(';'); return { t: 'Assert', c, m, line }; }
      case 'class': case 'interface': case 'enum': case 'abstract': case 'static': return { t: 'LocalClass', decl: typeDecl(mods()), line };
      case 'final': if (is('class', pk(1))) { p++; return { t: 'LocalClass', decl: typeDecl({}), line }; } break;
      case 'else': err("illegal start of statement ('else' without 'if')");
      case 'case': case 'default': err(`orphaned ${t.v}`);
    }
    if (isLocalDecl() || (t.t === 'kw' && PRIM.has(t.v) && !is('.', pk(1)) && !is('[', pk(1)) || (is('final') && true))) return localDecl(false);
    const e = expr(); if (!['Asg', 'Call', 'New', 'Pre', 'Post', 'Lambda', 'CtorCall'].includes(e.t) && !(e.t === 'Name' && false)) { if (e.t !== 'SwitchE') err('not a statement', t); }
    expect(';'); return { t: 'ExprS', e, line };
  }
  function switchBody(isExpr) {
    const line = tk().line; p++; expect('('); const sel = expr(); expect(')'); expect('{'); const cases = [];
    while (!is('}')) {
      const cl = tk().line; let labels = null, arrow = false;
      if (accept('default')) { labels = null; } else { expect('case'); labels = []; do { if (is('default')) { p++; labels.push({ t: 'Default' }); } else labels.push(ternary()); } while (accept(',')); }
      if (accept('->')) { arrow = true; let body; if (is('{')) body = [block()]; else if (is('throw')) body = [stmt()]; else { const e = expr(); expect(';'); body = [{ t: isExpr ? 'Yield' : 'ExprS', e, line: cl }]; } cases.push({ labels, arrow, body, line: cl }); }
      else { expect(':'); const body = []; while (!is('case') && !is('default') && !is('}')) body.push(stmt()); cases.push({ labels, arrow, body, line: cl }); }
    }
    p++; return { t: isExpr ? 'SwitchE' : 'Switch', sel, cases, line };
  }
  // ---------------------------------------------------------------- expressions
  function arguments_() { expect('('); const a = []; if (!is(')')) do { a.push(expr()); } while (accept(',')); expect(')'); return a; }
  function arrInit() { const line = tk().line; expect('{'); const elems = []; while (!is('}')) { elems.push(is('{') ? arrInit() : expr()); if (!accept(',')) break; } expect('}'); return { t: 'ArrInit', elems, line }; }
  function expr() { return assignment(); }
  const AOPS = new Set(['=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>=', '>>>=']);
  function assignment() {
    const l = ternary(), t = tk();
    if (t.t === 'op' && AOPS.has(t.v)) { if (!['Name', 'Field', 'Index'].includes(l.t)) err('unexpected type: required variable, found value', t); p++; const r = is('{') && t.v === '=' ? arrInit() : assignment(); return { t: 'Asg', op: t.v, l, r, line: t.line }; }
    return l;
  }
  function ternary() { const c = binary(0); if (is('?')) { const line = tk().line; p++; const a = is('(') || true ? assignment() : null; expect(':'); const b = lambdaOr(ternary); return { t: 'Cond', c, a, b, line }; } return c; }
  const lambdaOr = f => f();
  const PREC = [['||'], ['&&'], ['|'], ['^'], ['&'], ['==', '!='], ['<', '>', '<=', '>=', 'instanceof'], ['<<', '>>', '>>>'], ['+', '-'], ['*', '/', '%']];
  function binary(lv) {
    if (lv >= PREC.length) return unary();
    let l = binary(lv + 1);
    for (; ;) {
      const t = tk(); if (!((t.t === 'op' || t.t === 'kw') && PREC[lv].includes(t.v))) return l;
      p++;
      if (t.v === 'instanceof') { accept('final'); const ty = ptype(); let bind = null; if (isId()) bind = ident(); l = { t: 'InstOf', e: l, type: ty, bind, line: t.line }; continue; }
      l = { t: 'Bin', op: t.v, l, r: binary(lv + 1), line: t.line };
    }
  }
  function unary() {
    const t = tk();
    if (t.t === 'op') {
      if (t.v === '++' || t.v === '--') { p++; return { t: 'Pre', op: t.v, e: unary(), line: t.line }; }
      if (t.v === '-' || t.v === '+' || t.v === '!' || t.v === '~') { p++; if (t.v === '-' && tk().t === 'num' && !is('.', pk(1))) { const n = tk(); p++; return postfix({ t: 'Lit', v: -n.v, kind: n.kind, line: t.line }); } return { t: 'Un', op: t.v, e: unary(), line: t.line }; }
      if (t.v === '(') {
        // lambda
        let d = 0, q = p; for (; q < T.length; q++) { if (is('(', T[q])) d++; else if (is(')', T[q])) { d--; if (d === 0) break; } }
        if (is('->', T[q + 1])) return lambda();
        const c = spec(() => { p++; const ty = type(); if (!is(')')) throw new Fail(); const nx = pk(1); p++; const prim = PRIM.has(ty.n) && ty.d === 0; if (!prim && !(nx.t === 'id' || nx.t === 'str' || nx.t === 'chr' || nx.t === 'num' || (nx.t === 'op' && ['(', '!', '~'].includes(nx.v)) || (nx.t === 'kw' && ['this', 'new', 'super', 'true', 'false', 'null', 'switch'].includes(nx.v)))) throw new Fail(); if (prim && nx.t === 'op' && ['*', '/', '%', '<', '>', '==', '&&', '||', ')', ';', ','].includes(nx.v)) throw new Fail(); return ty; });
        if (c) return { t: 'Cast', type: c, e: unary(), line: t.line };
      }
    }
    return postfix(primary());
  }
  function lambda() { const line = tk().line; const ps = []; if (isId()) ps.push(ident()); else { expect('('); if (!is(')')) do { mods(); if (isId() && (is(',', pk(1)) || is(')', pk(1)))) ps.push(ident()); else { ptype(); accept('...'); ps.push(ident()); } } while (accept(',')); expect(')'); } expect('->'); const body = is('{') ? block() : expr(); return { t: 'Lambda', params: ps, body, line }; }
  function primary() {
    const t = tk(), line = t.line;
    switch (t.t) {
      case 'num': p++; return { t: 'Lit', v: t.v, kind: t.kind, line };
      case 'str': p++; return { t: 'Lit', v: t.v, kind: 'String', line };
      case 'chr': p++; return { t: 'Lit', v: t.v, kind: 'char', line };
      case 'id': if (is('->', pk(1))) return lambda(); p++; if (is('(')) return { t: 'Call', o: null, n: t.v, args: arguments_(), line }; return { t: 'Name', n: t.v, line };
      case 'kw':
        switch (t.v) {
          case 'true': case 'false': p++; return { t: 'Lit', v: t.v === 'true', kind: 'boolean', line };
          case 'null': p++; return { t: 'Lit', v: null, kind: 'null', line };
          case 'this': p++; if (is('(')) return { t: 'CtorCall', sup: false, args: arguments_(), line }; return { t: 'This', line };
          case 'super': p++; if (is('(')) return { t: 'CtorCall', sup: true, args: arguments_(), line }; return { t: 'Super', line };
          case 'new': return creator();
          case 'switch': return switchBody(true);
          default: if (PRIM.has(t.v)) { const ty = type(); if (is('::')) { return { t: 'Name', n: ty.n, line }; } expect('.'); expect('class'); return { t: 'ClassLit', type: ty, line }; }
        }
        break;
      case 'op': if (t.v === '(') { p++; const e = expr(); expect(')'); return { t: 'Paren', e, line }; }
    }
    err(t.t === 'eof' ? 'reached end of file while parsing' : `illegal start of expression` + (t.t !== 'eof' ? ` ('${t.v}')` : ''));
  }
  function creator() {
    const line = tk().line; p++; skipAnn(); const t = tk(); let n;
    let full = ''; if (t.t === 'kw' && PRIM.has(t.v)) { n = t.v; p++; } else { n = ident(); full = n; typeArgs(); while (accept('.')) { n = ident(); full += '.' + n; typeArgs(); } }
    if (is('[')) { const dims = []; let extra = 0; while (is('[')) { p++; if (is(']')) { p++; extra++; } else { dims.push(expr()); expect(']'); } } let init = null; if (is('{')) init = arrInit(); return { t: 'NewArr', type: { n, d: 0 }, dims, extra, init, line }; }
    const args = arguments_(); let body = null;
    if (is('{')) { body = { k: 'class', name: '', sup: n, ifaces: [], members: [], mods: {}, line, file, consts: [], anon: true }; classBody(body); }
    return { t: 'New', type: n, q: full, args, body, line };
  }
  function postfix(e) {
    for (; ;) {
      const t = tk();
      if (t.t !== 'op') return e;
      if (t.v === '.') {
        p++; if (is('<')) typeArgs();
        if (accept('new')) { p--; const c = creator(); c.outer = e; e = c; continue; }
        if (is('class')) { p++; e = { t: 'ClassLit', type: { n: e.n || '?', d: 0 }, line: t.line }; continue; }
        if (is('this')) { p++; e = { t: 'This', q: e.n, line: t.line }; continue; }
        if (is('super')) { p++; e = { t: 'Super', q: e.n, line: t.line }; continue; }
        const nm = ident(); if (is('(')) e = { t: 'Call', o: e, n: nm, args: arguments_(), line: tk().line === t.line ? t.line : t.line }; else e = { t: 'Field', o: e, n: nm, line: t.line };
      } else if (t.v === '[') { p++; const i = expr(); expect(']'); e = { t: 'Index', a: e, i, line: t.line }; }
      else if (t.v === '++' || t.v === '--') { p++; e = { t: 'Post', op: t.v, e, line: t.line }; }
      else if (t.v === '::') { p++; const nm = accept('new') ? 'new' : ident(); e = { t: 'MRef', o: e, n: nm, line: t.line }; }
      else return e;
    }
  }
  return compilationUnit();
}
APKB.parseJava = parse; APKB.ParseError = ParseError;
})(typeof window !== 'undefined' ? window : globalThis);
