# Super Speedy Plugins skills

Agent Skills for work that Super Speedy Plugins' WordPress plugins hand over to an AI assistant. A
skill is a folder holding a `SKILL.md` file of instructions, plus any scripts it needs. Once installed,
Claude reads the instructions when a task calls for them and runs the scripts itself.

| Skill | What it does |
|---|---|
| [`term-descriptions`](term-descriptions/) | Rewrites weak or repetitive category and tag descriptions in a term CSV downloaded from the Data tab of Super Speedy Imports, so each one is distinct and factual, and checks that nothing else in the file changed before it goes back through **+ New Import** |
| [`parallel-dev`](parallel-dev/) | Gives every AI agent, branch or test suite its own isolated local WordPress site at `<scenario>.<plugin>.localhost`, created in seconds on native nginx, PHP-FPM and MariaDB, so a half-saved file in one plugin cannot break the site another agent is testing. Also tells the agent to load test data in bulk rather than with one WP-CLI call per product. Needs an agent that runs shell commands on your machine, such as Claude Code; it does not work in claude.ai. The one-time server setup is in [`setup.md`](parallel-dev/setup.md) |
| [`plugin-security-review`](plugin-security-review/) | An adversarial security review of a WordPress or WooCommerce plugin. It first builds an evidence bundle (every entry point, input, sink, output, state change, dependency and money path, tied to the exact source revision), then traces each candidate from source to sink and fills a complete security coverage ledger. Writes a dated report into the plugin's `.code-reviews/` folder, which it keeps out of Git. Needs an agent that reads files and runs shell commands, such as Claude Code |
| [`plugin-updates`](plugin-updates/) | Applies waiting plugin updates on a staging site: reads each release's changelog and code changes, measures the site before and after with the free Super Speedy Performance Analysis plugin, finds which plugin slowed a page down, and recommends update, wait or roll back for each. It never touches the live site: it generates a script you run on live yourself, which refuses to change anything unless the site and every plugin version match what was tested. Needs an agent that runs shell commands, such as Claude Code, and WP-CLI on staging |
| [`one-by-one`](one-by-one/) | When work is waiting on several of your decisions, asks them one at a time instead of in one wall of text: each question with its context, options, a recommendation and full links, and each answer written down before the next question. Works in any Claude surface, including a claude.ai chat |
| [`woocommerce-performance-diagnosis`](woocommerce-performance-diagnosis/) | Diagnoses a slow WooCommerce store's back end: gathers the store's facts read-only (versions, HPOS, catalogue and order size, autoload, cron and Action Scheduler backlog, object and page cache, largest tables and indexes), measures the key pages with the free Super Speedy Performance Analysis plugin, and writes a Markdown report that ties every finding to its evidence and gives the free fix first. Asks before every change and never changes settings on a live store. Needs an agent that runs shell commands, such as Claude Code, and WP-CLI on the store |

Each skill follows the open [Agent Skills specification](https://agentskills.io/specification) and
uses only the frontmatter fields that claude.ai uploads accept (`name`, `description`, `license`,
`compatibility`, `metadata`).

## Install a skill in Claude (claude.ai and the desktop app)

Skills need code execution, and are available on the Free, Pro, Max, Team and Enterprise plans.

1. Download the skill folder as a ZIP. The ZIP must contain the folder itself at its root, for
   example `term-descriptions/SKILL.md`, not the files loose. From a copy of this repository:
   `zip -r term-descriptions.zip term-descriptions`
2. In Claude, go to **Settings > Capabilities** and make sure code execution is on. On Team and
   Enterprise plans an owner turns skills on for the organisation first.
3. Still in **Settings**, choose **Skills** under **Customize**.
4. Click **+ Add** at the top right, choose to upload a skill, and pick the ZIP.
5. Make sure the skill's toggle is on.

Claude then uses the skill when a conversation matches its description. For this one, upload the CSV
and ask Claude to rewrite the term descriptions.

## Install all six in Claude Code as a plugin

This repository is also a Claude Code plugin marketplace, `superspeedyplugins`, holding one plugin,
`super-speedy`, that contains all six skills. Inside a Claude Code session, run:

```
/plugin marketplace add superspeedyplugins/skills
/plugin install super-speedy@superspeedyplugins
```

On Claude Code 2.1.275 or later, one command does both:

```
/plugin install super-speedy --marketplace superspeedyplugins/skills
```

From your shell instead, `claude plugin marketplace add superspeedyplugins/skills` and then
`claude plugin install super-speedy@superspeedyplugins`. Restart Claude Code, or run `/reload-plugins`,
to load it.

Plugin skills carry the plugin's name, so you run them as `/super-speedy:term-descriptions`,
`/super-speedy:parallel-dev`, `/super-speedy:plugin-security-review`, `/super-speedy:plugin-updates`,
`/super-speedy:one-by-one` and `/super-speedy:woocommerce-performance-diagnosis`. Claude also uses each
one on its own when a request matches its description.

To get later versions, run `claude plugin update super-speedy@superspeedyplugins`, or turn on
auto-update for the marketplace in `/plugin`. To remove it, `claude plugin uninstall super-speedy@superspeedyplugins`.

The plugin adds skills only: no hooks, MCP servers, commands, agents or background processes. When a
skill runs a script, Claude runs it on your computer through its usual permission prompts. The scripts
work on the sites and repositories you point them at, and download WordPress themes and plugin versions
from wordpress.org; none of them sends data to Super Speedy Plugins.

## Install a skill in Claude Code by copying it

To install one skill without the plugin, copy its folder into one of these:

- `~/.claude/skills/term-descriptions/` to use it in every project on your computer;
- `.claude/skills/term-descriptions/` inside a project, to use it in that project and share it
  through the project's repository.

Claude Code picks up the new skill without a restart. It uses it when a request matches, or you can
run it directly with `/term-descriptions`.

## Install a skill for the Claude API

Upload the folder through the Skills API and pass its `skill_id` with the code execution tool. See
[Using Agent Skills with the API](https://platform.claude.com/docs/en/build-with-claude/skills-guide).
Skills do not sync between claude.ai, Claude Code and the API: install a skill in each place you use
it.

## Using another AI assistant

The Term Descriptions add-on's **Download for AI rewriting** gives a ZIP with the CSV and an
`INSTRUCTIONS.md` written for that download: the counts the checks found, the largest groups of
repeated text and the rules for the rewrite. Attach the CSV to any assistant that accepts file uploads,
paste the whole of `INSTRUCTIONS.md` into the chat, and answer its questions about your shop.

Without the skill, the assistant cannot check its own output, so check the returned file yourself
before importing: the same header, the same number of rows, and nothing changed except the
`term_taxonomy.description` column. With Python 3 installed, the skill's script does that check for
you:

```
python3 term-descriptions/scripts/term_csv.py validate original.csv rewritten.csv
```

`term-descriptions/INSTRUCTIONS.template.md` is the template that `INSTRUCTIONS.md` is built from.

## Where `plugin-security-review` came from

Hakan (`hakan_nedim` on the Super Speedy Plugins Discord), a long-standing customer, shared a plugin review skill
with us: a single 1,247-line file, itself a portable edition of an agency's in-house review skill. We split it into
a shared evidence foundation and focused specialist reviews (security, performance, logic, WooCommerce,
architecture, standards, internationalisation, accessibility, mobile and RTL, wordpress.org compliance, user
experience and removability), then adapted the security review to run on its own. Thank you, Hakan.

## Tests

```
python3 term-descriptions/tests/run_tests.py
parallel-dev/tests/run-tests.sh
parallel-dev/tests/test-setup-ubuntu.sh   # needs Docker
node plugin-security-review/tests/prepare-storage.test.mjs
node plugin-security-review/tests/validate-evidence.test.mjs
PU_TEST_WP_PATH=/path/to/throwaway/wordpress plugin-updates/tests/run-tests.sh
WPD_TEST_WP_PATH=/path/to/throwaway/woocommerce woocommerce-performance-diagnosis/tests/run-tests.sh
```

The `parallel-dev` tests start their own unprivileged nginx and PHP-FPM from the skill's config templates on
port 18081, then create, serve, break, reset and delete real sites with the skill's scripts. They need the
same packages as the skill and touch no system config. `test-setup-ubuntu.sh` reads the Ubuntu steps out of
`setup.md` and runs them, unchanged apart from starting services by hand, on a clean `ubuntu:24.04` container.

The `plugin-security-review` tests prove the evidence storage and the bundle validator against temporary Git
repositories with Node.js alone. They do not run a review.

The `plugin-updates` tests generate live scripts and run them against a real, throwaway WordPress site with
real wordpress.org plugins: refusing the wrong site, a version that differs from the one tested and a zip whose
checksum differs, then updating, backing up and refusing a second run. Never point them at a site you care about.

The `woocommerce-performance-diagnosis` tests run the store-facts script through WP-CLI on a real, throwaway
WooCommerce site with HPOS on and some orders: they check its counts against WordPress's own, that the catalogue,
order and Action Scheduler tables are unchanged afterwards, and that no billing email or last name from the site's
real orders appears in its output. With Performance Analysis active and one completed run, they also build the
evidence digest from that real report.

The `term-descriptions` tests use the Python 3 standard library only. They drive the script as the skill does, on a real Super Speedy
Imports term export and on synthetic files covering byte order marks, CRLF line endings, embedded
newlines, quotes, commas and formula-escaped cells.

## Licence

GPL 3. See [LICENSE](LICENSE).

## For maintainers: plugin layout and versions

The repository root is both the marketplace root and the plugin root. `.claude-plugin/marketplace.json`
lists the plugin with `"source": "./"`, and `.claude-plugin/plugin.json` sets `"skills": ["./"]`, so
every `<skill>/SKILL.md` folder at the root is part of the plugin without moving anything. A new skill
folder at the root joins the plugin automatically; add it to the table above.

`plugin.json` sets `version`. Raise it in every commit that changes a skill, or users who installed the
plugin keep the old copy: `claude plugin update` compares that field, not the commit. Run
`claude plugin validate --strict --profile directory .` before pushing.

## Sources for the install steps

Plugin and marketplace steps checked on 19 November 2026:

- [Create a marketplace](https://code.claude.com/docs/en/plugin-marketplaces) and the [marketplace reference](https://code.claude.com/docs/en/plugins/marketplace-reference.md)
- [Plugin manifest reference](https://code.claude.com/docs/en/plugins-reference) (`skills` paths, `"."` as the plugin root)
- [Publish and distribute a plugin](https://code.claude.com/docs/en/plugins/publish.md) (install commands and updates)

Skill steps checked on 30 September 2026:

- [Use skills in Claude](https://support.claude.com/en/articles/12512180-use-skills-in-claude) (claude.ai upload steps and plans)
- [How to create custom skills](https://support.claude.com/en/articles/12512198-how-to-create-custom-skills) (ZIP layout, 200-character description limit)
- [Extend Claude with skills](https://code.claude.com/docs/en/skills) (Claude Code skill locations and the fields claude.ai uploads accept)
- [Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) (where skills work, name and description rules)
- [Agent Skills specification](https://agentskills.io/specification) (frontmatter fields and folder layout)
