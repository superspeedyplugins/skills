#!/usr/bin/env python3
"""Work safely with a Super Speedy Imports term CSV (Data tab download) while rewriting descriptions.

Python 3.8+, standard library only.

  term_csv.py inspect  FILE [--json] [--top N]
      Rows, taxonomies, source site, extra columns, empty descriptions, findings and the largest
      groups with their shared text.
  term_csv.py show     FILE [--group KEY] [--finding KEY] [--done REWRITES] [--offset N] [--limit N]
      One JSON object per row, for reading a batch. Values are shown as stored in WordPress (the
      export's formula-escape apostrophe removed).
  term_csv.py split    FILE OUTDIR [--rows 200]
      Batches of at most N rows, each with the original header. Row bytes are copied exactly.
  term_csv.py merge    ORIGINAL OUTPUT BATCH...
      Reassemble batches into the original row order. Refuses missing, unknown or repeated rows.
  term_csv.py apply    ORIGINAL REWRITES OUTPUT
      Write a copy of ORIGINAL where only the description cells named in REWRITES change. Every
      other byte is copied. REWRITES is JSON Lines:
        {"term_id": 123, "description": "<p>New text.</p>"}
        {"term_id": 124, "keep": true, "reason": "nothing reliable to say"}
      The last line for a term wins. Then validates OUTPUT against ORIGINAL.
  term_csv.py validate ORIGINAL REWRITTEN
      Header identical, same rows in the same order, every column except
      term_taxonomy.description unchanged. Reports changed and unchanged descriptions.

Exit status: 0 success, 1 validation failure (the file must not be imported), 2 unusable input.

The CSV is parsed by hand rather than with the csv module so that each record's exact bytes are
known: split, merge and apply copy untouched rows and cells byte for byte, including quoting,
embedded newlines (LF or CRLF), a UTF-8 byte order mark and the export's formula escaping (a cell
starting with = + - @ tab or CR is written with a leading apostrophe, which the importer removes).
"""
import argparse
import html
import json
import os
import re
import sys
from collections import Counter, OrderedDict

DESC = 'term_taxonomy.description'
ID = 'terms.term_id'
BASE = ['terms.term_id', 'taxonomy', 'ssi_source_site', 'terms.name', 'terms.slug', 'term_taxonomy.parent',
        'parent_path', 'term_taxonomy.count', 'term_taxonomy.description']
ADDON = ['ssitd_findings', 'ssitd_group', 'ssitd_group_text']
BOM = '﻿'
FORMULA = '=+-@\t\r'


class InputError(Exception):
    """The file cannot be used at all (exit 2)."""


class Record:
    __slots__ = ('start', 'end', 'fields', 'spans', 'eol', 'line')

    def __init__(self, start, line):
        self.start, self.line = start, line
        self.end, self.fields, self.spans, self.eol = start, [], [], ''


class CsvFile:
    def __init__(self, path, strict=True):
        self.path = path
        try:
            with open(path, 'rb') as f:
                data = f.read()
        except OSError as e:
            raise InputError('%s: %s' % (path, e.strerror))
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError as e:
            raise InputError('%s is not UTF-8 (byte %d). Save it as "CSV UTF-8" and try again.' % (path, e.start))
        self.bom = text.startswith(BOM)
        self.text = text[1:] if self.bom else text
        records = parse(self.text, path)
        if not records:
            raise InputError('%s is empty.' % path)
        self.header_record = records[0]
        self.header = records[0].fields
        self.records = records[1:]
        self.col = {name: i for i, name in enumerate(self.header)}
        missing = [c for c in (ID, DESC) if c not in self.col]
        if strict and missing:
            raise InputError('%s has no %s column, so it is not a Super Speedy Imports term download. '
                             'Header: %s' % (path, ' or '.join(missing), ','.join(self.header)))
        if strict:
            for n, r in enumerate(self.records, 1):
                if len(r.fields) != len(self.header):
                    raise InputError('%s row %d (line %d) has %d fields; the header has %d.'
                                     % (path, n, r.line, len(r.fields), len(self.header)))

    def raw(self, record):
        return self.text[record.start:record.end]

    def value(self, record, column):
        i = self.col.get(column)
        return record.fields[i] if i is not None and i < len(record.fields) else ''

    def key(self, record):
        return tuple(self.value(record, c) for c in (ID, 'taxonomy', 'ssi_source_site'))

    @property
    def eol(self):
        return self.header_record.eol or '\n'


def parse(text, path):
    """Split text into records, remembering each record's and each field's character span."""
    records, i, n, line = [], 0, len(text), 1
    while i < n:
        rec = Record(i, line)
        while True:
            start = i
            if i < n and text[i] == '"':
                parts, j = [], i + 1
                while True:
                    k = text.find('"', j)
                    if k < 0:
                        raise InputError('%s: a quote opened on line %d is never closed.' % (path, line))
                    parts.append(text[j:k])
                    if k + 1 < n and text[k + 1] == '"':
                        parts.append('"')
                        j = k + 2
                    else:
                        j = k + 1
                        break
                # Anything between the closing quote and the next separator is kept, as PHP does.
                m = j
                while m < n and text[m] not in ',\r\n':
                    m += 1
                parts.append(text[j:m])
                value, i = ''.join(parts), m
            else:
                m = i
                while m < n and text[m] not in ',\r\n':
                    m += 1
                value, i = text[i:m], m
            line += text.count('\n', start, i)
            rec.fields.append(value)
            rec.spans.append((start, i))
            if i < n and text[i] == ',':
                i += 1
                continue
            break
        if text.startswith('\r\n', i):
            rec.eol = '\r\n'
        elif i < n:
            rec.eol = text[i]
        i += len(rec.eol)
        line += rec.eol.count('\n') or (1 if rec.eol == '\r' else 0)
        rec.end = i
        if rec.fields == [''] and records:
            records[-1].end = rec.end  # a blank line: keep its bytes with the record before it
            continue
        records.append(rec)
    return records


def stored(value):
    """The value WordPress holds: the importer removes the export's formula-escape apostrophe."""
    if len(value) > 1 and value[0] == "'" and value[1] in FORMULA:
        return value[1:]
    return value


def is_numeric(value):
    try:
        float(value)
        return True
    except ValueError:
        return False


def encode_cell(value):
    """Quote a new description the way the export writes a cell, formula escape included."""
    if value and value[0] in FORMULA and not is_numeric(value):
        value = "'" + value
    return '"' + value.replace('"', '""') + '"'


TAG = re.compile(r'<[^>]*>')


def plain(value):
    return re.sub(r'\s+', ' ', html.unescape(TAG.sub(' ', stored(value)))).strip()


def normalised(value):
    return re.sub(r'[^\w ]+', '', plain(value).lower()).strip()


def write_text(path, text, bom):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8', newline='') as f:
        f.write((BOM if bom else '') + text)
    os.replace(tmp, path)


def eol_name(eol):
    return {'\r\n': 'CRLF', '\n': 'LF', '\r': 'CR'}.get(eol, 'none')


# ---------------------------------------------------------------- inspect

def cmd_inspect(a):
    f = CsvFile(a.file)
    taxonomies = Counter(f.value(r, 'taxonomy') for r in f.records)
    sites = Counter(f.value(r, 'ssi_source_site') for r in f.records)
    has_addon = all(c in f.col for c in ADDON)
    findings, groups, texts = Counter(), Counter(), {}
    if has_addon:
        for r in f.records:
            for k in f.value(r, 'ssitd_findings').split(','):
                if k.strip():
                    findings[k.strip()] += 1
            g = f.value(r, 'ssitd_group')
            if g:
                groups[g] += 1
                texts.setdefault(g, stored(f.value(r, 'ssitd_group_text')))
    top = sorted(groups.items(), key=lambda kv: (-kv[1], kv[0]))[:a.top]
    data = OrderedDict([
        ('file', a.file), ('rows', len(f.records)), ('columns', len(f.header)), ('bom', f.bom),
        ('line_ending', eol_name(f.header_record.eol)),
        ('taxonomies', dict(taxonomies)), ('source_sites', dict(sites)),
        ('extra_columns', [c for c in f.header if c not in BASE and c not in ADDON]),
        ('has_addon_columns', has_addon),
        ('empty_descriptions', sum(1 for r in f.records if not plain(f.value(r, DESC)))),
        ('findings', dict(findings.most_common())),
        ('group_count', len(groups)),
        ('groups', [OrderedDict([('group', g), ('size', n), ('text', texts[g])]) for g, n in top]),
    ])
    if a.json:
        print(json.dumps(data, ensure_ascii=False, indent=1))
        return 0
    print('%s: %d rows, %d columns, UTF-8 %s BOM, %s line endings'
          % (a.file, data['rows'], data['columns'], 'with' if f.bom else 'without', data['line_ending']))
    print('Taxonomy: ' + ', '.join('%s (%d)' % kv for kv in taxonomies.most_common()))
    print('Source site: ' + ', '.join('%s (%d)' % kv for kv in sites.most_common()))
    if data['extra_columns']:
        print('Extra columns (keep unchanged): ' + ', '.join(data['extra_columns']))
    print('Empty descriptions: %d' % data['empty_descriptions'])
    if not has_addon:
        print('No ssitd_* columns: a plain term download, so there are no findings or groups. Work row by row.')
        return 0
    print('Findings: ' + (', '.join('%s %d' % kv for kv in findings.most_common()) or 'none'))
    print('Groups: %d%s' % (len(groups), ', largest first:' if groups else ''))
    for g in data['groups']:
        print('  %-24s %5d terms  %s' % (g['group'], g['size'], json.dumps(g['text'], ensure_ascii=False)))
    if len(groups) > len(top):
        print('  ... %d more (use --top)' % (len(groups) - len(top)))
    return 0


# ---------------------------------------------------------------- show

def read_rewrites(path):
    """Return (OrderedDict term_id -> entry, number of superseded lines)."""
    try:
        with open(path, encoding='utf-8-sig') as fh:
            content = fh.read()
    except OSError as e:
        raise InputError('%s: %s' % (path, e.strerror))
    entries = []
    if content.lstrip().startswith('['):
        try:
            entries = json.loads(content)
        except ValueError as e:
            raise InputError('%s is not valid JSON: %s' % (path, e))
    else:
        for n, line in enumerate(content.splitlines(), 1):
            if line.strip():
                try:
                    entries.append(json.loads(line))
                except ValueError as e:
                    raise InputError('%s line %d is not valid JSON: %s' % (path, n, e))
    out, superseded = OrderedDict(), 0
    for n, e in enumerate(entries, 1):
        if not isinstance(e, dict) or 'term_id' not in e:
            raise InputError('%s entry %d has no term_id.' % (path, n))
        tid = str(e['term_id']).strip()
        if e.get('keep') is True:
            e = {'keep': True}
        elif isinstance(e.get('description'), str):
            if not e['description'].strip():
                raise InputError('%s entry %d (term %s) has an empty description. The importer ignores empty '
                                 'cells; to leave a term as it is, write {"term_id": %s, "keep": true}.'
                                 % (path, n, tid, tid))
        else:
            raise InputError('%s entry %d (term %s) needs a "description" string or "keep": true.' % (path, n, tid))
        if tid in out:
            superseded += 1
            del out[tid]
        out[tid] = e
    return out, superseded


def cmd_show(a):
    f = CsvFile(a.file)
    done = read_rewrites(a.done)[0] if a.done else {}
    extra = [c for c in f.header if c not in BASE and c not in ADDON]
    shown = skipped = 0
    for n, r in enumerate(f.records, 1):
        if a.group and f.value(r, 'ssitd_group') != a.group:
            continue
        if a.finding and a.finding not in [k.strip() for k in f.value(r, 'ssitd_findings').split(',')]:
            continue
        if f.value(r, ID) in done:
            continue
        if skipped < a.offset:
            skipped += 1
            continue
        if a.limit is not None and shown >= a.limit:
            break
        item = OrderedDict([('row', n), ('term_id', f.value(r, ID)), ('taxonomy', f.value(r, 'taxonomy')),
                            ('name', stored(f.value(r, 'terms.name'))), ('slug', f.value(r, 'terms.slug')),
                            ('parent_path', stored(f.value(r, 'parent_path'))),
                            ('count', f.value(r, 'term_taxonomy.count')),
                            ('description', stored(f.value(r, DESC)))])
        if 'ssitd_findings' in f.col:
            item['findings'] = f.value(r, 'ssitd_findings')
            item['group'] = f.value(r, 'ssitd_group')
        meta = {c: stored(f.value(r, c)) for c in extra if f.value(r, c)}
        if meta:
            item['other'] = meta
        print(json.dumps(item, ensure_ascii=False))
        shown += 1
    return 0


# ---------------------------------------------------------------- split / merge

def cmd_split(a):
    if a.rows < 1:
        raise InputError('--rows must be at least 1.')
    f = CsvFile(a.file)
    os.makedirs(a.outdir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(a.file))[0]
    head = f.raw(f.header_record)
    if not f.header_record.eol:
        head += '\n'
    names = []
    for b in range(0, max(len(f.records), 1), a.rows):
        chunk = f.records[b:b + a.rows]
        name = os.path.join(a.outdir, '%s.part-%04d.csv' % (stem, b // a.rows + 1))
        write_text(name, head + ''.join(f.raw(r) for r in chunk), f.bom)
        names.append(name)
        print('%s  rows %d-%d' % (name, b + 1, b + len(chunk)))
    print('%d rows in %d batches.' % (len(f.records), len(names)))
    return 0


def cmd_merge(a):
    orig = CsvFile(a.original)
    order = [orig.key(r) for r in orig.records]
    if len(set(order)) != len(order):
        raise InputError('%s repeats a term ID, so rows cannot be matched by ID.' % a.original)
    wanted = set(order)
    found, problems = {}, []
    for path in a.batches:
        b = CsvFile(path)
        if b.header != orig.header:
            problems.append('%s: header differs from %s.' % (path, a.original))
            continue
        for r in b.records:
            k = b.key(r)
            if k not in wanted:
                problems.append('%s: term %s is not in %s.' % (path, k[0], a.original))
            elif k in found:
                problems.append('%s: term %s appears more than once across the batches.' % (path, k[0]))
            else:
                raw = b.raw(r)
                found[k] = raw
    missing = [k[0] for k in order if k not in found]
    if missing:
        problems.append('%d rows missing, first: %s' % (len(missing), ', '.join(missing[:10])))
    if problems:
        for p in problems[:25]:
            sys.stderr.write(p + '\n')
        sys.stderr.write('Not merged.\n')
        return 1
    parts = [orig.raw(orig.header_record)]
    for n, k in enumerate(order):
        raw = found[k]
        if n < len(order) - 1 and not raw.endswith(('\n', '\r')):
            raw += orig.eol
        parts.append(raw)
    write_text(a.output, ''.join(parts), orig.bom)
    print('Merged %d rows from %d batches into %s.' % (len(order), len(a.batches), a.output))
    return 0


# ---------------------------------------------------------------- apply

def cmd_apply(a):
    if os.path.abspath(a.output) == os.path.abspath(a.original):
        raise InputError('Write to a new file, not over %s.' % a.original)
    f = CsvFile(a.original)
    rewrites, superseded = read_rewrites(a.rewrites)
    ids = Counter(f.value(r, ID) for r in f.records)
    unknown = [t for t in rewrites if ids[t] == 0]
    if unknown:
        raise InputError('Term IDs not in %s: %s' % (a.original, ', '.join(unknown[:20])))
    repeated = [t for t in rewrites if ids[t] > 1]
    if repeated:
        raise InputError('%s has more than one row for term IDs %s, so a rewrite cannot be matched.'
                         % (a.original, ', '.join(repeated[:20])))
    d = f.col[DESC]
    parts, pos, changed, kept, same = [], 0, 0, 0, 0
    for r in f.records:
        e = rewrites.get(f.value(r, ID))
        if not e:
            continue
        if e.get('keep'):
            kept += 1
            continue
        new = e['description']
        if new == stored(r.fields[d]):
            same += 1
            continue
        s, t = r.spans[d]
        parts.append(f.text[pos:s])
        parts.append(encode_cell(new))
        pos = t
        changed += 1
    parts.append(f.text[pos:])
    write_text(a.output, ''.join(parts), f.bom)
    print('Wrote %s: %d changed, %d kept as they are, %d identical to the current text, %d rows not in %s.'
          % (a.output, changed, kept, same, len(f.records) - changed - kept - same, os.path.basename(a.rewrites)))
    if superseded:
        print('%d earlier entries were replaced by a later entry for the same term.' % superseded)
    return validate(f, CsvFile(a.output, strict=False))


# ---------------------------------------------------------------- validate

def validate(orig, new):
    problems, notes, warnings = [], [], []
    if orig.bom != new.bom:
        notes.append('Byte order mark %s (harmless).' % ('removed' if orig.bom else 'added'))
    if eol_name(orig.header_record.eol) != eol_name(new.header_record.eol):
        notes.append('Line endings changed from %s to %s (harmless).'
                     % (eol_name(orig.header_record.eol), eol_name(new.header_record.eol)))
    if new.header != orig.header:
        for i in range(max(len(orig.header), len(new.header))):
            o = orig.header[i] if i < len(orig.header) else '(none)'
            w = new.header[i] if i < len(new.header) else '(none)'
            if o != w:
                problems.append('Header differs at column %d: expected %r, found %r.' % (i + 1, o, w))
                break
    if len(new.records) != len(orig.records):
        problems.append('Different row count: original %d, rewritten %d.' % (len(orig.records), len(new.records)))
    changed = unchanged = emptied = 0
    rewritten = []
    if new.header == orig.header:
        d = orig.col[DESC]
        order_reported = False
        for n, (o, w) in enumerate(zip(orig.records, new.records), 1):
            if len(w.fields) != len(orig.header):
                problems.append('Row %d (line %d) has %d fields; the header has %d.'
                                % (n, w.line, len(w.fields), len(orig.header)))
                continue
            if w.fields[orig.col[ID]] != o.fields[orig.col[ID]]:
                if not order_reported:
                    problems.append('Row %d: terms.term_id is %s, expected %s. Rows were dropped, added or '
                                    'reordered; every row must stay in its original place.'
                                    % (n, new.value(w, ID), orig.value(o, ID)))
                    order_reported = True
                continue
            for i, name in enumerate(orig.header):
                if i != d and w.fields[i] != o.fields[i]:
                    problems.append('Row %d (term %s): column %s changed from %r to %r.'
                                    % (n, orig.value(o, ID), name, o.fields[i][:60], w.fields[i][:60]))
            if w.fields[d] == o.fields[d]:
                unchanged += 1
                continue
            changed += 1
            if not w.fields[d].strip():
                emptied += 1
                continue
            rewritten.append((orig.value(o, ID), w.fields[d]))
    for tid, text in rewritten:
        if re.search(r'\{(name|parent)\}', text):
            warnings.append('Term %s: the description still contains a {name} or {parent} placeholder.' % tid)
        if re.search(r'<\s*(script|style|iframe|form)\b|\son\w+\s*=', text, re.I):
            warnings.append('Term %s: the description contains script, style, iframe, form or on* attributes.' % tid)
    seen = {}
    for tid, text in rewritten:
        seen.setdefault(normalised(text), []).append(tid)
    for text, tids in seen.items():
        if text and len(tids) > 1:
            warnings.append('Terms %s were given the same description.' % ', '.join(tids[:10]))
    print('Descriptions: %d changed, %d unchanged.' % (changed, unchanged))
    if emptied:
        print('%d descriptions were emptied. The importer ignores empty cells, so those terms keep their '
              'current description.' % emptied)
    for line in notes:
        print('Note: ' + line)
    for line in warnings[:25]:
        print('Warning: ' + line)
    if len(warnings) > 25:
        print('Warning: ... and %d more.' % (len(warnings) - 25))
    if problems:
        for line in problems[:25]:
            print('FAIL: ' + line)
        if len(problems) > 25:
            print('FAIL: ... and %d more.' % (len(problems) - 25))
        print('FAILED: %s must not be imported.' % new.path)
        return 1
    print('PASSED: %s keeps every row, the header and every column except %s.' % (new.path, DESC))
    return 0


def cmd_validate(a):
    return validate(CsvFile(a.original), CsvFile(a.rewritten, strict=False))


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = p.add_subparsers(dest='cmd')
    s = sub.add_parser('inspect')
    s.add_argument('file')
    s.add_argument('--json', action='store_true')
    s.add_argument('--top', type=int, default=20)
    s = sub.add_parser('show')
    s.add_argument('file')
    s.add_argument('--group')
    s.add_argument('--finding')
    s.add_argument('--done')
    s.add_argument('--offset', type=int, default=0)
    s.add_argument('--limit', type=int)
    s = sub.add_parser('split')
    s.add_argument('file')
    s.add_argument('outdir')
    s.add_argument('--rows', type=int, default=200)
    s = sub.add_parser('merge')
    s.add_argument('original')
    s.add_argument('output')
    s.add_argument('batches', nargs='+')
    s = sub.add_parser('apply')
    s.add_argument('original')
    s.add_argument('rewrites')
    s.add_argument('output')
    s = sub.add_parser('validate')
    s.add_argument('original')
    s.add_argument('rewritten')
    a = p.parse_args(argv)
    if not a.cmd:
        p.print_help()
        return 2
    try:
        return globals()['cmd_' + a.cmd](a)
    except InputError as e:
        sys.stderr.write('Error: %s\n' % e)
        return 2


if __name__ == '__main__':
    sys.exit(main())
