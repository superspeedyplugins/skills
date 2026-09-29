<!--
Template for the INSTRUCTIONS.md that the Term Descriptions add-on puts in the "Download for AI
rewriting" ZIP next to the CSV. The add-on removes this comment and replaces each {{placeholder}}
with plain text. There are no loops or conditions: list placeholders arrive already rendered.
Single-brace {name} and {parent} are NOT placeholders; they appear in shared text and stay as they are.

{{site_name}}        Site title, e.g. Example Outdoor Shop
{{site_url}}         Home URL, the same value as the CSV's ssi_source_site column
{{taxonomy_label}}   Plural label, e.g. Product categories
{{taxonomy}}         Taxonomy name, e.g. product_cat
{{term_count}}       Rows in the CSV, e.g. 1,204
{{csv_filename}}     The CSV's name inside the ZIP
{{generated_date}}   Date of the analysis, e.g. 30 September 2026
{{check_counts}}     Markdown list, one line per check that flagged at least one of these terms,
                     largest first: "- Same template with the name swapped: 412 terms"
{{group_summaries}}  Markdown list of up to 10 groups, largest first, shared text in double quotes,
                     newlines collapsed, cut at 200 characters with an ellipsis:
                     "- 412 terms (template-7c1e2a): "Shop our range of {name} at great prices.""
                     When there are no groups: "- None."
{{thresholds}}       Markdown list of the settings used, e.g.
                     "- Short: under 50 characters of text"
                     "- Mostly boilerplate: 60% or more of the text is sentences shared by 5 or more terms"
                     "- Near duplicate: 80% or more similar"
                     "- Says nothing: the name plus fewer than 3 other words"
                     "- Only terms in use: yes"
{{skill_url}}        https://github.com/superspeedyplugins/skills/tree/main/term-descriptions
-->
# Rewriting {{taxonomy_label}} descriptions for {{site_name}}

`{{csv_filename}}` holds {{term_count}} terms from {{taxonomy_label}} (`{{taxonomy}}`) on {{site_url}},
chosen with the Data tab of Super Speedy Imports on {{generated_date}}. Give this file and the CSV to
your AI assistant.

## What the checks found

{{check_counts}}

The largest groups of repeated text. `{name}` stands for each term's own name, `{parent}` for its
parent's.

{{group_summaries}}

Settings used:

{{thresholds}}

## Instructions for the AI

Rewrite the descriptions in the attached CSV so that each one is useful and different from the rest.

1. Change only the `term_taxonomy.description` column. The header row, every other column and every
   row, in its original order, stay exactly as they are, character for character. Some cells start
   with an apostrophe, such as `'-10°C`: that is deliberate, so keep it.
2. Before you start, ask me what the shop sells and to whom, the tone and language, the length (if I
   don't say: 40 to 80 words, less when there is little to say) and whether to keep any shared
   delivery or returns text (if I don't say: drop it).
3. Terms with the same `ssitd_group` repeat each other, and `ssitd_group_text` shows the repeated text.
   Write each one in a group from that term's own name, its `parent_path` and anything specific in its
   current description, so the descriptions differ in substance. Rephrasing the shared text is not
   enough.
4. Use only facts from the term's name, its parent path, its current description, the other columns
   and what I tell you. Never invent sizes, materials, brands, prices, stock, delivery times or claims
   such as "best" or "top-rated".
5. Match the current format. Allowed HTML: `<p>`, `<ul>`, `<ol>`, `<li>`, `<strong>`, `<em>`, `<br>`
   and `<a>`. Keep existing links unchanged and add none. Leave no `{name}` or `{parent}` in the text.
6. If you cannot improve a description, leave its cell exactly as it is.
7. Give me back the complete CSV as a file, UTF-8, with the same header and all {{term_count}} rows.

## Importing the result

Before importing, check that nothing but the descriptions changed. The import finds each term by its
Term ID, so a changed ID would update the wrong term.

In WordPress, go to **Super Speedy > Imports**, click **+ New Import** and upload the returned CSV.
With the Term Descriptions add-on active, it is recognised as term data and each row is matched to
its term by Term ID, because the file came from this site. Check the preview, then run the import.
Only descriptions change. An empty description cell never overwrites anything, and HTML is written
exactly as it is in the file.

## Using Claude?

If you use Claude, our term-descriptions skill does this for you: {{skill_url}}

It reads the CSV itself, works through large files in batches, and checks that only the descriptions
changed before it gives the file back.
