#!/usr/bin/env python3
import os
import re
import sys
import zipfile
from pathlib import Path


_ARR_VARS = re.compile(r'\b([a-zA-Z][a-zA-Z0-9_]{0,3})\s*=\s*\{')

def _find_array(src: str):
    for m in _ARR_VARS.finditer(src):
        start = m.end()
        body, end = _extract_brace_body(src, start)
        if len(body) > 200 and ('"' in body or "'" in body):
            return m.group(1), body, m.start(), end
    return None

def _extract_brace_body(src: str, start: int):
    depth = 0
    i = start
    n = len(src)
    while i < n:
        c = src[i]
        if c in ('"', "'"):
            i = _skip_string(src, i) + 1
            continue
        if c == '[' and i + 1 < n and src[i+1] == '[':
            i = _skip_long_string(src, i) + 1
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            if depth == 0:
                return src[start:i], i + 1
            depth -= 1
        i += 1
    return src[start:], n

def _skip_string(src: str, i: int) -> int:
    q = src[i]
    i += 1
    while i < len(src):
        c = src[i]
        if c == '\\':
            i += 2
            continue
        if c == q:
            return i
        i += 1
    return i

def _skip_long_string(src: str, i: int) -> int:
    i += 2
    while i < len(src) - 1:
        if src[i] == ']' and src[i+1] == ']':
            return i + 1
        i += 1
    return i

def _parse_elements(body: str) -> list:
    items = []
    depth = 0
    start = 0
    in_str = False
    str_char = ''
    i = 0
    while i < len(body):
        c = body[i]
        if in_str:
            if c == '\\' and i + 1 < len(body):
                i += 2
                continue
            if c == str_char:
                in_str = False
        elif c in ('"', "'"):
            in_str = True
            str_char = c
        elif c in '({[':
            depth += 1
        elif c in ')}]':
            depth -= 1
        elif c == ',' and depth == 0:
            elem = body[start:i].strip()
            if elem:
                items.append(elem)
            start = i + 1
        i += 1
    tail = body[start:].strip()
    if tail:
        items.append(tail)
    return items

def _is_plain_string(s: str) -> bool:
    return (s.startswith('"') and s.endswith('"') and len(s) >= 2) or \
           (s.startswith("'") and s.endswith("'") and len(s) >= 2)

def _is_plain_number(s: str) -> bool:
    return bool(re.match(r'^-?\d+\.?\d*$', s))

def build_rg_map(src: str):
    result = _find_array(src)
    if result is None:
        return None, {}, 0, 0
    var, body, a_start, a_end = result
    elems = _parse_elements(body)
    rg = {}
    for idx, e in enumerate(elems):
        lua_idx = idx + 1
        stripped = e.strip()
        if _is_plain_string(stripped):
            rg[lua_idx] = stripped
        elif _is_plain_number(stripped):
            try:
                fv = float(stripped)
                if fv == int(fv):
                    rg[lua_idx] = str(int(fv))
                else:
                    rg[lua_idx] = stripped
            except ValueError:
                pass
    return var, rg, a_start, a_end


def _inline_one_var(src: str, varname: str, rg: dict) -> str:
    # *inlines a single array-alias variable throughout the source*
    pat = re.compile(re.escape(varname) + r'\[\s*([\d]+\.?\d*)\s*\]')
    def replacer(m):
        idx = int(float(m.group(1)))
        return rg.get(idx, m.group(0))
    for _ in range(3):
        new = pat.sub(replacer, src)
        if new == src:
            break
        src = new
    return src

def inline_constants(src: str, var: str, rg: dict, also_aliases: bool = True) -> str:
    if not rg:
        return src
    src = _inline_one_var(src, var, rg)
    if not also_aliases:
        return src
    alias_pat = re.compile(r'\blocal\s+([a-zA-Z]\w{0,3})\s*=\s*' + re.escape(var) + r'\b')
    aliases = sorted(set(m.group(1) for m in alias_pat.finditer(src)))
    for alias in aliases:
        src = _inline_one_var(src, alias, rg)
    return src

def inline_remaining_aliases(src: str, var: str, rg: dict) -> str:
    if not rg:
        return src
    alias_pat = re.compile(r'\blocal\s+([a-zA-Z]\w{0,3})\s*=\s*' + re.escape(var) + r'\b')
    aliases = sorted(set(m.group(1) for m in alias_pat.finditer(src)))
    for alias in aliases:
        src = _inline_one_var(src, alias, rg)
    return src


def format_semicolons(src: str) -> str:
    # *splits packed LuaST code into one statement per line*
    n = len(src)
    out_parts = []
    depth = 0
    in_str = False
    str_char = '\0'
    seg_start = 0
    i = 0
    while i < n:
        c = src[i]
        if in_str:
            if c == '\\':
                i += 2
                continue
            if c == str_char:
                in_str = False
            i += 1
            continue
        if c == '[' and i + 1 < n and src[i + 1] == '[':
            j = src.find(']]', i + 2)
            i = (j + 2) if j != -1 else n
            continue
        if c == '-' and i + 1 < n and src[i + 1] == '-':
            j = src.find('\n', i + 2)
            if j == -1:
                seg = src[seg_start:i].strip()
                if seg:
                    out_parts.append(seg)
                comment = src[i:].strip()
                if comment:
                    out_parts.append(comment)
                seg_start = n
                break
            seg = src[seg_start:i].strip()
            if seg:
                out_parts.append(seg)
            comment = src[i:j].strip()
            if comment:
                out_parts.append(comment)
            seg_start = j + 1
            i = j + 1
            continue
        if c in ('"', "'"):
            in_str = True
            str_char = c
            i += 1
            continue
        if c in '({[':
            depth += 1
            i += 1
            continue
        if c in ')}]':
            depth -= 1
            i += 1
            continue
        if depth == 0:
            if c == ';' or c == '\n':
                seg = src[seg_start:i].strip()
                if seg:
                    out_parts.append(seg)
                seg_start = i + 1
        i += 1
    if seg_start < n:
        seg = src[seg_start:].strip()
        if seg:
            out_parts.append(seg)
    return '\n'.join(out_parts)


_RE_STATE_ONLY     = re.compile(r'^[a-z]\w{0,3}\s*=\s*\d+\.?\d*\s*$')
_RE_STATE_ARITH    = re.compile(r'^[a-z]\w{0,3}\s*=\s*\d+\.?\d*\s*[-+]\s*[a-z]\w{0,3}\s*$')
_RE_STATE_BXOR     = re.compile(r'^[a-z]\w{0,3}\s*=\s*bit32\.bxor\([a-z]\w{0,3},\s*\w+\[')
_RE_CF_IF_BREAK    = re.compile(r'^(?:if|elseif)\s+[a-z]\w{0,3}\s*(?:<|>|==|<=|>=|~=)\s*\d+\.?\d*\s+then\s+(?:break|continue)\s*$')
_RE_CF_ELSEIF_ONLY = re.compile(r'^elseif\s+[a-z]\w{0,3}\s*(?:==|<|>|<=|>=)\s*\d+\.?\d*\s+then\s*$')
_RE_WHILE_TRUE     = re.compile(r'^while\s+true\s+do\b')
_RE_BARE_DO        = re.compile(r'^do\s*$')
_RE_CONTINUE_END   = re.compile(r'^continue\s+end\s*$')
_RE_END_STACK      = re.compile(r'^(?:end\s+){2,}$')
_RE_NIL_ASSIGN     = re.compile(r'^(?:[a-z]\w{0,3}\s*=\s*nil\s*;?\s*)+$')
_RE_MULTI_NIL      = re.compile(r'^local\s+(?:[a-zA-Z]\w{0,3}\s*,\s*)*[a-zA-Z]\w{0,3}\s*=\s*nil(?:\s*,\s*nil)*\s*$')
_RE_LOCAL_NILREG   = re.compile(r'^local\s+[a-z]\w{0,3}\s*(?:=\s*nil\s*)?$')
_RE_LUAST_HDR      = re.compile(r'^--\s*generated by luast', re.I)
_RE_HEX_STR        = re.compile(r'^local\s+\w{1,4}\s*=\s*"(?:\\x[0-9a-fA-F]{2}){3,}"\s*$')
_RE_MAGIC_NUM      = re.compile(r'^local\s+\w{1,4}\s*=\s*\d{7,}\s*$')
_RE_STATE_DECL     = re.compile(r'^local\s+([a-z][a-zA-Z0-9]{0,2})\s*=\s*nil\s*$')
_RE_CF_IF_STATE    = re.compile(r'^if\s+([a-z]\w{0,3})\s*(?:<|>|==|<=|>=)\s*\d+\.?\d*\s+then\s*$')
_RE_WHILE_CF_INLINE = re.compile(r'^while\s+true\s+do\s+([a-z]\w{0,3})\s*=\s*\d+\s*-\s*\1')
_RE_BARE_NIL       = re.compile(r'^nil\s*$')


def _looks_like_cf_var(name: str) -> bool:
    return bool(name) and len(name) <= 3 and name.isalpha() and name.islower()

def strip_cf_lines(lines: list) -> list:
    out = []
    cf_vars = set()
    for ln in lines:
        s = ln.strip()
        if _RE_STATE_ARITH.match(s):
            cf_vars.add(s.split('=')[0].strip())
        if _RE_STATE_BXOR.match(s):
            cf_vars.add(s.split('=')[0].strip())

    for ln in lines:
        s = ln.strip()
        if not s:
            continue
        if _RE_LUAST_HDR.match(s):
            continue
        if _RE_HEX_STR.match(s):
            continue
        if _RE_MAGIC_NUM.match(s):
            continue
        if _RE_BARE_NIL.match(s):
            continue
        if _RE_NIL_ASSIGN.match(s):
            parts = [p.strip().split('=')[0].strip() for p in s.split(';') if p.strip()]
            if all(_looks_like_cf_var(p) for p in parts if p):
                continue
        if _RE_MULTI_NIL.match(s):
            lhs = s.split('=')[0].replace('local', '').strip()
            varnames = [v.strip() for v in lhs.split(',')]
            if all(len(v) <= 3 and v.replace('_', '').isalnum() for v in varnames if v):
                continue
        if _RE_STATE_ONLY.match(s):
            varname = s.split('=')[0].strip()
            if varname in cf_vars or _looks_like_cf_var(varname):
                continue
        if _RE_STATE_ARITH.match(s):
            continue
        if _RE_STATE_BXOR.match(s):
            continue
        if _RE_CF_IF_BREAK.match(s):
            continue
        if _RE_CF_ELSEIF_ONLY.match(s):
            continue
        if _RE_WHILE_CF_INLINE.match(s):
            continue
        if _RE_WHILE_TRUE.match(s):
            rest = s[len('while true do'):].strip()
            if not rest or re.match(r'^[a-z]\w{0,3}\s*=\s*\d+', rest):
                continue
        if _RE_BARE_DO.match(s):
            continue
        if _RE_CONTINUE_END.match(s):
            continue
        if _RE_END_STACK.match(s):
            continue
        m = _RE_STATE_DECL.match(s)
        if m and _looks_like_cf_var(m.group(1)):
            continue
        m = _RE_CF_IF_STATE.match(s)
        if m and (m.group(1) in cf_vars or _looks_like_cf_var(m.group(1))):
            continue
        out.append(ln)
    return out


def remove_array_body(src: str, var: str, a_start: int, a_end: int) -> str:
    return src[:a_start] + 'nil' + src[a_end:]

def clean_numbers(src: str) -> str:
    return re.sub(r'(?<!\d)(\d+)\.(?!\d)', r'\1', src)

def compact_whitespace(src: str) -> str:
    src = re.sub(r'\n{3,}', '\n\n', src)
    lines = [ln.rstrip() for ln in src.split('\n')]
    return '\n'.join(lines).strip() + '\n'


def deobfuscate(src: str) -> str:
    var, rg, a_start, a_end = build_rg_map(src)
    if rg:
        src = inline_constants(src, var, rg, also_aliases=True)
        result2 = _find_array(src)
        if result2:
            _, _, a2_start, a2_end = result2
            src = remove_array_body(src, var, a2_start, a2_end)
        src = inline_remaining_aliases(src, var, rg)
    src = clean_numbers(src)
    src = format_semicolons(src)
    lines = src.split('\n')
    lines = strip_cf_lines(lines)
    src = '\n'.join(lines)
    src = compact_whitespace(src)
    return src

def deobfuscate_file(in_path: str, out_path: str) -> str:
    try:
        src = open(in_path, encoding='latin-1').read()
    except Exception as e:
        return f'ERROR reading: {e}'

    is_luast = 'luast' in src[:200].lower()
    has_big_array = bool(re.search(r'\b\w{1,4}\s*=\s*\{[^}]{500,}', src[:4000]))
    is_obf = is_luast or has_big_array

    try:
        result = deobfuscate(src)
    except Exception as e:
        import traceback
        return f'ERROR deobf: {e}\n{traceback.format_exc()[:300]}'

    try:
        os.makedirs(os.path.dirname(out_path) or '.', exist_ok=True)
        open(out_path, 'w', encoding='utf-8').write(result)
    except Exception as e:
        return f'ERROR writing: {e}'

    orig_size = len(src)
    new_size = len(result)
    reduction = 100 * (1 - new_size / max(orig_size, 1))
    tag = '[LuaST]' if is_luast else '[obf?]' if is_obf else '[clean]'
    return f'{tag} {orig_size//1024}KB→{new_size//1024}KB ({reduction:.0f}% smaller)'


def main():
    args = sys.argv[1:]
    if not args:
        print('Usage: luast_deobf.py <input.lua> [output.lua]')
        print('       luast_deobf.py <directory>')
        sys.exit(0)

    target = args[0]
    out_arg = args[1] if len(args) > 1 else None

    if os.path.isdir(target):
        files = sorted(f for f in Path(target).iterdir() if f.suffix in ('.lua', '.luau'))
        out_dir = out_arg or os.path.join(os.path.dirname(target), 'deobf_out')
        out_dir = os.path.abspath(out_dir)
        os.makedirs(out_dir, exist_ok=True)
        print(f'[*] Deobfuscating {len(files)} files → {out_dir}')
        ok = err = 0
        for f in files:
            out_path = os.path.join(out_dir, f.name)
            status = deobfuscate_file(str(f), out_path)
            print(f'  {f.name}: {status}')
            if 'ERROR' in status:
                err += 1
            else:
                ok += 1
        print(f'[*] Done: {ok} ok, {err} errors')
        zip_path = out_dir + '.zip'
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            for f in sorted(Path(out_dir).iterdir()):
                zf.write(f, f.name)
        print(f'[*] Archive → {zip_path}')
        return zip_path
    else:
        out_path = out_arg or re.sub(r'\.(lua[u]?)$', r'_deobf.\1', target)
        if out_path == target:
            out_path = target + '_deobf.lua'
        status = deobfuscate_file(target, out_path)
        print(f'{os.path.basename(target)}: {status}')
        print(f'Output → {out_path}')


if __name__ == '__main__':
    main()
