"""Generate the synthetic fixtures in the shape of a real SSI term export plus the add-on's columns.

Quoting mirrors PHP fputcsv($h, $row, ',', '"', ''): a field is quoted when it contains a comma,
double quote, CR, LF, tab or space. Formula escaping mirrors superspeedyimports_csv_escape_formulas().
"""
import os, sys

OUT = sys.argv[1]
SITE = 'https://shop.example.com'
HEADER = ['terms.term_id', 'taxonomy', 'ssi_source_site', 'terms.name', 'terms.slug', 'term_taxonomy.parent',
          'parent_path', 'term_taxonomy.count', 'term_taxonomy.description', 'termmeta.display_type',
          'ssitd_findings', 'ssitd_group', 'ssitd_group_text']


def is_numeric(v):
    try:
        float(v)  # PHP's is_numeric() also accepts surrounding whitespace
        return True
    except ValueError:
        return False


def escape(row):
    out = []
    for v in row:
        v = str(v)
        if v != '' and not is_numeric(v) and v[0] in '=+-@\t\r':
            v = "'" + v
        out.append(v)
    return out


def field(v):
    if any(c in v for c in ',"\r\n\t '):
        return '"' + v.replace('"', '""') + '"'
    return v


def line(row, eol='\n'):
    return ','.join(field(v) for v in escape(row)) + eol


# Store tree: id -> (name, slug, parent, count, display_type)
T = {}
def term(i, name, slug, parent=0, count=0, display='products'):
    T[i] = (name, slug, parent, count, display)

term(101, 'Clothing', 'clothing', 0, 214, 'subcategories')
term(102, 'Footwear', 'footwear', 0, 96, 'subcategories')
term(103, 'Camping', 'camping', 0, 131, 'subcategories')
term(104, 'Accessories', 'accessories', 0, 158, 'subcategories')
term(111, 'Jackets', 'jackets', 101, 88, 'subcategories')
term(112, 'Base Layers', 'base-layers', 101, 34)
term(121, 'Waterproof Jackets', 'waterproof-jackets', 111, 41)
term(122, 'Insulated Jackets', 'insulated-jackets', 111, 23)
term(123, 'Softshell Jackets', 'softshell-jackets', 111, 12)
term(124, 'Fleeces', 'fleeces', 101, 29)
term(125, 'Kids Jackets', 'kids-jackets', 111, 12)
term(126, 'Merino Base Layers', 'merino-base-layers', 112, 18)
term(131, 'Walking Boots', 'walking-boots', 102, 38)
term(132, 'Trail Shoes', 'trail-shoes', 102, 27)
term(133, 'Wellies', 'wellies', 102, 9)
term(134, 'Walking Socks', 'walking-socks', 102, 22)
term(141, 'Tents', 'tents', 103, 31)
term(142, 'Sleeping Bags', 'sleeping-bags', 103, 26)
term(143, 'Sleeping Mats', 'sleeping-mats', 103, 14)
term(144, 'Camping Stoves', 'camping-stoves', 103, 11)
term(145, 'Camping Chairs', 'camping-chairs', 103, 8)
term(146, 'Cool Boxes', 'cool-boxes', 103, 6)
term(151, 'Rucksacks', 'rucksacks', 104, 44)
term(152, 'Head Torches', 'head-torches', 104, 15)
term(153, 'Walking Poles', 'walking-poles', 104, 13)
term(154, 'Water Bottles', 'water-bottles', 104, 17)
term(155, 'Hats', 'hats', 104, 21)
term(156, 'Gloves', 'gloves', 104, 19)
term(157, 'Maps & Guides', 'maps-guides', 104, 40)
term(158, 'Misc 2', 'misc-2', 104, 0)


def path(i):
    names = []
    while i:
        names.insert(0, T[i][0])
        i = T[i][2]
    return ' > '.join(names)


TMPL = 'Shop our range of {name} at great prices. Free UK delivery on orders over £50.'
RET = 'Not happy with your order? Return it within 30 days for a full refund. Returns are free for UK customers.'
NEAR = 'Great quality outdoor gear for every adventure, in stock and ready to ship.'

# id -> (description, findings, group, group_text)
D = {
    101: ('<p> </p>\n', 'missing', '', ''),
    102: ('', 'missing', '', ''),
    103: ('', 'missing', '', ''),
    111: ('', 'missing', '', ''),
    121: ('<p>Shop our range of Waterproof Jackets at great prices. Free UK delivery on orders over £50.</p>', 'template', 'template-7c1e2a', TMPL),
    122: ('<p>Shop our range of Insulated Jackets at great prices. Free UK delivery on orders over £50.</p>', 'template', 'template-7c1e2a', TMPL),
    123: ('<p>Shop our range of Softshell Jackets at great prices. Free UK delivery on orders over £50.</p>', 'template', 'template-7c1e2a', TMPL),
    124: ('<p>Shop our range of Fleeces at great prices. Free UK delivery on orders over £50.</p>', 'template', 'template-7c1e2a', TMPL),
    131: ('<p>Shop our range of Walking Boots at great prices. Free UK delivery on orders over £50.</p>', 'template', 'template-7c1e2a', TMPL),
    132: ('<p>Shop our range of Trail Shoes at great prices. Free UK delivery on orders over £50.</p>', 'template', 'template-7c1e2a', TMPL),
    133: ('<p>Shop our range of Wellies at great prices. Free UK delivery on orders over £50.</p>', 'template', 'template-7c1e2a', TMPL),
    141: ('<p>Shop our range of Tents at great prices. Free UK delivery on orders over £50.</p>', 'template', 'template-7c1e2a', TMPL),
    142: ('<p>Sleeping bags for summer camping and colder nights.</p><p>' + RET + '</p>', 'boilerplate', 'boilerplate-41d09f', RET),
    143: ('<p>Foam and self-inflating mats.</p><p>' + RET + '</p>', 'boilerplate', 'boilerplate-41d09f', RET),
    144: ('<p>Gas stoves, fuel and pans.</p><p>' + RET + '</p>', 'boilerplate', 'boilerplate-41d09f', RET),
    151: ('<p>Daypacks and bigger rucksacks for multi-day trips. See our <a href="https://shop.example.com/rucksack-fitting/">rucksack fitting guide</a>.</p><p>' + RET + '</p>', 'boilerplate', 'boilerplate-41d09f', RET),
    152: ('<p>Rechargeable head torches.</p><p>' + RET + '</p>', 'boilerplate', 'boilerplate-41d09f', RET),
    153: ('Great quality outdoor gear for every adventure, in stock and ready to ship.', 'near_duplicate', 'near-9b3e70', NEAR),
    154: ('Great quality outdoor kit for every adventure, in stock and ready to ship today.', 'near_duplicate', 'near-9b3e70', NEAR),
    134: ('Great quality outdoor gear for every single adventure, all in stock and ready to ship.', 'near_duplicate', 'near-9b3e70', NEAR),
    112: ('<p>Base Layers</p>', 'name_only,short', '', ''),
    126: ('Merino base layers', 'name_only,short', '', ''),
    155: ('Coming soon', 'placeholder,short', '', ''),
    156: ('Lorem ipsum dolor sit amet.', 'placeholder,short', '', ''),
    158: ('TBC', 'placeholder,short', '', ''),
    104: ('<p>Top brands at low prices.</p>', 'duplicate,short', 'duplicate-0e5f11', 'Top brands at low prices.'),
    145: ('<p>Top brands at low prices.</p>', 'duplicate,short', 'duplicate-0e5f11', 'Top brands at low prices.'),
    146: ('<p>Top brands at low prices!</p>', 'duplicate,short', 'duplicate-0e5f11', 'Top brands at low prices.'),
    125: ('Warm, dry jackets.', 'short', '', ''),
    157: ('OS maps, 1:25k.', 'short', '', ''),
}
assert len(D) == 30, len(D)

rows = [line(HEADER)]
for i in sorted(D):
    name, slug, parent, count, display = T[i]
    desc, findings, group, gtext = D[i]
    rows.append(line([i, 'product_cat', SITE, name, slug, parent, path(i), count, desc, display, findings, group, gtext]))
open(os.path.join(OUT, 'addon-sample-30.csv'), 'w', encoding='utf-8', newline='').write(''.join(rows))

# Edge cases: formula escapes, embedded newlines (LF and CRLF), commas, quotes, unicode, spaces-only.
EH = ['terms.term_id', 'taxonomy', 'ssi_source_site', 'terms.name', 'terms.slug', 'term_taxonomy.parent',
      'parent_path', 'term_taxonomy.count', 'term_taxonomy.description', 'termmeta.zzd_seo_title', 'termmeta.sort_order',
      'ssitd_findings', 'ssitd_group', 'ssitd_group_text']
E = [
    [201, 'product_tag', SITE, '-10°C Sleeping Bags', '10c-sleeping-bags', 0, '-10°C Sleeping Bags', 4, '=HYPERLINK("http://example.com","click")', '+Warm bags, "rated" to -10°C', '-5', 'placeholder', '', ''],
    [202, 'product_tag', SITE, '@home', 'at-home', 0, '@home', 2, '', '', '', 'missing', '', ''],
    [203, 'product_tag', SITE, 'Café & Bistro Sets', 'cafe-bistro-sets', 0, 'Café & Bistro Sets', 7, '<p>Line one,\nline two with "quotes", and a comma.</p>\n<ul>\n<li>Übergrößen</li>\n</ul>', 'SEO: café, bistro', '3', 'template', 'template-aa01', 'Shop {name}, the best {name} around.'],
    [204, 'product_tag', SITE, 'Tents ⛺', 'tents-emoji', 0, 'Tents ⛺', 1, '<p>Windows line\r\nending inside a cell.</p>', 'Multi\r\nline meta', '', 'template', 'template-aa01', 'Shop {name}, the best {name} around.'],
    [205, 'product_tag', SITE, 'Spaces', 'spaces', 0, 'Spaces', 0, '   ', ' leading and trailing ', '', 'missing', '', ''],
    [206, 'product_tag', SITE, 'Tab\tName', 'tab-name', 0, 'Tab\tName', 0, '\tTabbed description', '', '0', 'short', '', ''],
    [207, 'product_tag', SITE, 'Plain', 'plain', 0, 'Plain', 12, 'NoQuotesNeeded', 'x', '10', 'name_only', '', ''],
    [208, 'product_tag', SITE, 'Quote "Mark"', 'quote-mark', 0, 'Quote "Mark"', 3, '""', '"', '', 'placeholder', '', ''],
]
rows = [line(EH)] + [line(r) for r in E]
edge = ''.join(rows)
open(os.path.join(OUT, 'edge-cases.csv'), 'w', encoding='utf-8', newline='').write(edge)
# Same records as saved by a Windows tool: UTF-8 BOM and CRLF record terminators (embedded newlines untouched).
crlf = '﻿' + ''.join(line(r, '\r\n') for r in [EH] + E)
open(os.path.join(OUT, 'edge-cases-crlf-bom.csv'), 'w', encoding='utf-8', newline='').write(crlf)
# No newline after the last record.
open(os.path.join(OUT, 'edge-cases-no-final-newline.csv'), 'w', encoding='utf-8', newline='').write(edge[:-1])
print('ok')
