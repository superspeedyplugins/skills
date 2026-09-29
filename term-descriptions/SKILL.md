---
name: term-descriptions
description: Rewrites weak or repetitive category and tag descriptions in a Super Speedy Imports term CSV, keeping every other cell intact so the file imports back. Use for any ssitd_ or term CSV.
license: GPL-3.0. Full text at https://www.gnu.org/licenses/gpl-3.0.html
compatibility: Needs Python 3 to run scripts/term_csv.py (standard library only). Works in claude.ai with code execution on, in Claude Code and through the API code execution tool.
metadata:
  author: Super Speedy Plugins
  version: "1.0.0"
---

# Rewriting term descriptions

The user has a CSV of taxonomy terms (product categories, tags, brands and so on) downloaded from the
Data tab of Super Speedy Imports, a WordPress import plugin. The descriptions in it are weak: missing,
too short, copied from term to term, or the same sentence with the name swapped. Your job is to write
each one a better, genuinely distinct description, and hand back a file that imports straight back
into the same site.

Every command below runs the helper in this skill's folder: `python3 scripts/term_csv.py` (the path is
relative to the skill folder). Never rewrite the CSV yourself with a spreadsheet library, pandas or
by hand. Re-quoting a single cell of another column is enough to break the import's matching, and the
helper exists so that only description cells change.

## The file

| Column | What it is | You may change it |
|---|---|---|
| `terms.term_id` | The term's ID on the site | Never |
| `taxonomy` | For example `product_cat`, `product_tag` | Never |
| `ssi_source_site` | The site the file came from. The import matches rows on Term ID only when this is its own URL | Never |
| `terms.name`, `terms.slug` | Name and slug | Never |
| `term_taxonomy.parent`, `parent_path` | Parent ID and path, `Clothing > Jackets > Waterproof Jackets` | Never |
| `term_taxonomy.count` | Products or posts using the term | Never |
| `term_taxonomy.description` | The description, HTML included | **Yes. The only column you change** |
| `termmeta.<key>` | Term metadata, for example an SEO title | Never, but read it for facts |
| `ssitd_findings` | Comma-separated checks the term failed | Never |
| `ssitd_group` | A key shared by terms whose descriptions repeat each other | Never |
| `ssitd_group_text` | The shared text or template, with `{name}` and `{parent}` where the term's own names were | Never |

Every row stays, in its original order, and the header stays as it is.

The `ssitd_` columns come from the Term Descriptions add-on. A plain download has no findings or
groups: work row by row. The findings are:

| Finding | Meaning |
|---|---|
| `missing` | No text at all (empty, or only tags and spaces) |
| `short` | Less text than the site's threshold |
| `duplicate` | The same text as other terms, ignoring case and punctuation |
| `template` | The same text once each term's name is replaced by `{name}` |
| `boilerplate` | Mostly sentences that many other terms share, such as a delivery or returns paragraph |
| `near_duplicate` | Almost the same as other terms apart from a few words |
| `name_only` | Says nothing beyond the term's name |
| `placeholder` | Lorem ipsum, "coming soon", "TBC", "test" and similar |

Read any other finding key by its plain meaning.

## 1. Look at the file

```
python3 scripts/term_csv.py inspect FILE.csv
```

This prints the row count, taxonomy, source site, extra columns, how many descriptions are empty, the
findings and the largest groups with their shared text. If the user also gave you an
`INSTRUCTIONS.md` from the same download, read it: it holds the store's name and the analysis.

## 2. Ask once, then work

Unless the user or `INSTRUCTIONS.md` has already said, ask these in one message and wait:

1. What does the shop sell, and to whom? Any facts you want every description to be able to rely on
   (brands stocked, where products are made, delivery area)?
2. Tone, and the language and spelling to write in. Default: the language of the existing
   descriptions and names, British or American spelling to match.
3. Length. Default: 40 to 80 words, less when there is little to say.
4. Shared delivery, returns or offer text found in the descriptions: keep it, shorten it to one
   closing sentence, or drop it? Default: drop it, because it is the repeated part the checks flagged
   and it belongs in the shop's page template, not in every category.

Don't ask anything else. If the user says "just do it", use the defaults and say which you used.

## 3. Facts: use only what you are given

A description may state only what one of these supports:

- the term's name, and its place in `parent_path` (its parent and, from the rest of the file, its
  siblings and children);
- the existing description, including its unique sentences and its links;
- other columns in the row, such as a `termmeta` SEO title;
- what the user told you about the shop.

Explaining what the name means in general is fine: what a softshell jacket is, what a base layer is
for, when people use a cool box. Claims about this shop's products are not, unless one of the sources
above makes them.

Never invent sizes, materials, brands, prices, discounts, stock levels, delivery times, ratings,
awards, certifications or comparisons ("best", "cheapest", "top-rated"). Do not quote
`term_taxonomy.count`: it changes as products are added. Existing marketing claims with nothing
behind them ("top brands at low prices", "in stock and ready to ship") are not facts to keep. If a
claim would be useful but you do not know it, leave it out. A plain, true description beats a vivid
invented one.

## 4. Work group by group

Groups are where the repetition is, so start there, largest first:

```
python3 scripts/term_csv.py show FILE.csv --group GROUP_KEY
```

For each group:

1. Read `ssitd_group_text` and decide what it contributes. Usually nothing specific: "Shop our range
   of {name} at great prices" is the template to get away from, not a structure to rephrase.
2. For every member, work out what is specific to it: what the name says the products are, what its
   parent says about context, how it differs from its siblings in the same group, and any unique
   sentence the old description already had (keep that sentence's facts).
3. Write each description from those specifics. Vary the opening and the structure across the group.
   Check: if you swapped two terms' names between their descriptions, would both still read fine?
   Then they are not distinct enough. Rewrite.
4. For `boilerplate` members, keep the unique part, expand it from the specifics, and treat the shared
   part as the user decided in step 2.

Then do the rest by finding, using `--done` so finished terms drop out:

```
python3 scripts/term_csv.py show FILE.csv --done rewrites.jsonl --limit 200
```

## 5. Leave a row alone when you cannot improve it

Record a term as kept, with a reason, when:

- the name gives nothing reliable to write from (`Misc 2`, `Tag 5`, an internal code) and the user has
  given no context for it;
- the existing description is already specific and correct (a `short` finding on a good one-line
  description is not a reason to pad it);
- the term looks like a utility term (for example `Uncategorized`), unless the user asked for it.

Kept rows are left exactly as they are in the output. List them for the user at the end, so they can
add context and run those again.

## 6. Format

- Match the existing format. If most descriptions in the file use HTML, write `<p>` paragraphs for
  every term. If they are plain text, write plain text.
- Allowed HTML: `<p>`, `<ul>`, `<ol>`, `<li>`, `<strong>`, `<em>`, `<br>` and `<a>`. HTML is imported
  exactly as written.
- Keep an existing link, with its `href` unchanged, when its sentence survives. Never add a link or a
  URL of your own.
- No headings, images, tables, scripts, styles, classes or inline `style` attributes.
- No `{name}` or `{parent}` placeholders in the output: write the real names.
- Write characters normally (`&`, quotes, `£`). Don't HTML-encode them.
- Open with what the category actually contains, in plain words. No "Welcome to", no "Discover our
  amazing range", no keyword stuffing, no exclamation marks.

## 7. Record your work in batches

Write each finished description, or each kept term, as one line of JSON appended to `rewrites.jsonl`
next to the CSV:

```
{"term_id": 121, "description": "<p>Waterproof jackets with taped seams ...</p>"}
{"term_id": 158, "keep": true, "reason": "no information in the name"}
```

Work in batches of about 200 rows and append after each batch, so a long file survives an interrupted
session. To resume, run `show` with `--done rewrites.jsonl`: it lists only the terms not yet done. If
a term appears twice, the later line wins, which is how you revise one.

After each batch, check your work so far:

```
python3 scripts/term_csv.py apply FILE.csv rewrites.jsonl FILE-rewritten.csv
```

A file of 20,000 rows is the same loop, more batches. If the work must be spread over separate
sessions or assistants, `split FILE.csv OUTDIR --rows 200` writes batches that each keep the header,
`apply` works on each batch, and `merge FILE.csv OUT.csv BATCH...` puts them back in the original
order. Then validate the merged file against the original.

## 8. Finish

1. Run `apply` one last time. It writes the output and validates it against the original. It must
   end with `PASSED`. If it prints `FAILED`, fix the cause and run it again; never hand over a file
   that failed.
2. Fix every `Warning:` line: a leftover `{name}`, or two terms given the same description.
3. To check a file produced some other way, run
   `python3 scripts/term_csv.py validate FILE.csv OTHER.csv`.
4. Give the user the rewritten CSV, the counts (changed, kept) and three to five before and after
   examples, including one from the largest group. List the kept terms and why.
5. Tell them how to import it:

   > In WordPress, go to **Super Speedy > Imports**, click **+ New Import** and upload the rewritten
   > file. With the Term Descriptions add-on active, Super Speedy Imports recognises it as term data
   > and matches each row to its term by Term ID, because the file came from the same site. Check the
   > preview, then run the import. Only descriptions change. An empty description cell never
   > overwrites anything, and HTML is written exactly as it is in the file.

The file only matches by Term ID on the site it was downloaded from. Imported anywhere else, rows
match by taxonomy and slug instead.
