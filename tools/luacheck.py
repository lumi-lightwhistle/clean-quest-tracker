"""Structural Lua 5.1 check: tokenizes, balances blocks and brackets, and lists free (global) names read."""
import re
import sys

KW = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in', 'local', 'nil',
      'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}
BACKSLASH = chr(92)


def tokens(src):
    i, n, line, out = 0, len(src), 1, []
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        if c.isspace():
            i += 1
            continue
        if src.startswith('--', i):
            m = re.match(r'--\[(=*)\[', src[i:])
            if m:
                close = ']' + m.group(1) + ']'
                j = src.find(close, i)
                if j < 0:
                    raise SystemExit(f'unclosed long comment line {line}')
                line += src[i:j].count('\n')
                i = j + len(close)
                continue
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        m = re.match(r'\[(=*)\[', src[i:])
        if m:
            close = ']' + m.group(1) + ']'
            j = src.find(close, i)
            if j < 0:
                raise SystemExit(f'unclosed long string line {line}')
            line += src[i:j].count('\n')
            out.append(('str', '', line))
            i = j + len(close)
            continue
        if c in '"\'':
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == BACKSLASH:
                    j += 1
                if src[j] == '\n':
                    raise SystemExit(f'newline in string line {line}')
                j += 1
            if j >= n:
                raise SystemExit(f'unclosed string line {line}')
            out.append(('str', src[i + 1:j], line))
            i = j + 1
            continue
        m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', src[i:])
        if m:
            w = m.group(0)
            out.append(('kw' if w in KW else 'name', w, line))
            i += len(w)
            continue
        m = re.match(r'0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+', src[i:])
        if m:
            out.append(('num', m.group(0), line))
            i += len(m.group(0))
            continue
        for op in ('...', '..', '==', '~=', '<=', '>='):
            if src.startswith(op, i):
                out.append(('op', op, line))
                i += len(op)
                break
        else:
            out.append(('op', c, line))
            i += 1
    return out


def check(path):
    src = open(path, encoding='utf-8').read()
    toks = tokens(src)
    stack, errs, pending_loop = [], [], 0
    pairs = {'(': ')', '[': ']', '{': '}'}
    for k, v, l in toks:
        if k == 'op' and v in pairs:
            stack.append((v, l))
        elif k == 'op' and v in ')]}':
            if not stack or pairs.get(stack[-1][0]) != v:
                errs.append(f'{path}:{l}: unexpected {v} (top {stack[-1] if stack else None})')
            else:
                stack.pop()
        elif k == 'kw':
            if v in ('while', 'for'):
                pending_loop += 1
                stack.append((v, l))
            elif v == 'do':
                if pending_loop:
                    pending_loop -= 1
                else:
                    stack.append(('do', l))
            elif v in ('function', 'if', 'repeat'):
                stack.append((v, l))
            elif v == 'end':
                if not stack or stack[-1][0] not in ('function', 'if', 'do', 'while', 'for'):
                    errs.append(f'{path}:{l}: unexpected end (top {stack[-1] if stack else None})')
                else:
                    stack.pop()
            elif v == 'until':
                if not stack or stack[-1][0] != 'repeat':
                    errs.append(f'{path}:{l}: unexpected until')
                else:
                    stack.pop()
    if stack:
        errs.append(f'{path}: unclosed {stack[-5:]}')
    return toks, errs


def free_names(toks):
    """Very rough: names not preceded by '.', ':' or 'local'/'function' decl and never declared local in file."""
    declared = set()
    for idx, (k, v, l) in enumerate(toks):
        if k == 'kw' and v in ('local', 'for', 'function') or (k == 'op' and v in ('(', ',')):
            pass
    locals_ = set()
    for idx, (k, v, l) in enumerate(toks):
        if k == 'name':
            prev = toks[idx - 1] if idx else ('', '', 0)
            if prev[0] == 'kw' and prev[1] in ('local', 'for'):
                locals_.add(v)
            if prev == ('kw', 'function', prev[2]) or (prev[0] == 'kw' and prev[1] == 'function'):
                locals_.add(v)
            # names in local lists / params / for lists
            j = idx - 1
            while j > 0 and toks[j][0] == 'op' and toks[j][1] == ',' and toks[j - 1][0] == 'name':
                j -= 2
            if j >= 0 and toks[j][0] == 'kw' and toks[j][1] in ('local', 'for'):
                locals_.add(v)
            if j >= 0 and toks[j][0] == 'op' and toks[j][1] == '(' and j > 0 and (
                    toks[j - 1][1] == 'function' or (toks[j - 2][1] == 'function' if j > 1 else False)
                    or toks[j - 1][0] == 'name' and j > 1 and toks[j - 2][1] in ('function', '.', ':')):
                locals_.add(v)
    free = {}
    for idx, (k, v, l) in enumerate(toks):
        if k != 'name':
            continue
        prev = toks[idx - 1] if idx else ('', '', 0)
        if prev[0] == 'op' and prev[1] in ('.', ':'):
            continue
        nxt = toks[idx + 1] if idx + 1 < len(toks) else ('', '', 0)
        if nxt[0] == 'op' and nxt[1] == '=' and prev[0] == 'op' and prev[1] in ('{', ','):
            continue  # table constructor key
        if v in locals_:
            continue
        free.setdefault(v, l)
    return free


if __name__ == '__main__':
    report_free = '--free' in sys.argv
    for p in [a for a in sys.argv[1:] if not a.startswith('--')]:
        toks, errs = check(p)
        print(p, 'OK' if not errs else '\n'.join(errs))
        if report_free:
            print('  free:', ' '.join(sorted(free_names(toks))))
