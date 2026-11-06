// A specialist review must not start on a bundle that no longer describes the source in
// front of it. validate-evidence.sh recomputes the fingerprint, checks the commit, checks
// every required inventory and its declared status, and reports the working-tree state in a
// way a reader can act on. Each check is proved here against a temporary repository.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const validator = resolve(here, '..', 'scripts', 'validate-evidence.sh');
const fingerprinter = resolve(here, '..', 'scripts', 'source-fingerprint.sh');
const root = mkdtempSync(join(tmpdir(), 'review-validate-test-'));
const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const repo = join(root, 'sample-plugin');
mkdirSync(repo, { recursive: true });
git(repo, 'init', '-q');
writeFileSync(join(repo, '.gitignore'), '/.data\n/.code-reviews\n');
writeFileSync(join(repo, 'plugin.php'), "<?php\n/**\n * Plugin Name: Sample\n * Version: 1.0.0\n */\n");
git(repo, 'add', '-A');
git(repo, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'fixture');
const head = git(repo, 'rev-parse', 'HEAD');
const headTree = git(repo, 'rev-parse', 'HEAD^{tree}');
const fingerprint = () => execFileSync('sh', [fingerprinter, repo], { encoding: 'utf8' }).trim();

const inventories = ['files', 'feature-surfaces', 'entry-points', 'inputs-and-sinks', 'hooks', 'state-changes', 'outputs', 'bootstrap-contexts', 'dependencies-and-network', 'money-and-authority'];
const statusKey = (name) => name.replaceAll('-', '_');
function bundle(id, overrides = {}) {
    const dir = join(root, 'evidence', id);
    rmSync(dir, { recursive: true, force: true });
    mkdirSync(join(dir, 'inventories'), { recursive: true });
    const statuses = {};
    for (const name of inventories) {
        statuses[statusKey(name)] = 'COMPLETE';
        writeFileSync(join(dir, 'inventories', name + '.md'), `# ${name}\n\n| symbol | file:line |\n|---|---|\n| sample | plugin.php:1 |\n`);
    }
    const manifest = {
        schema_version: 2,
        evidence_id: id,
        created_at: '2026-09-15T00:00:00Z',
        repository_path: repo,
        repository_slug: 'sample-plugin',
        plugin_root: repo,
        plugin_version: '1.0.0',
        head_commit: head,
        head_tree: headTree,
        git_status: 'clean',
        working_tree_changes: [],
        source_fingerprint: fingerprint(),
        runtime: { site_url: null, php: null, wordpress: null, woocommerce: null, action_scheduler: null },
        inventories: statuses,
        ...overrides.manifest,
    };
    writeFileSync(join(dir, 'manifest.json'), JSON.stringify(manifest, null, 2));
    writeFileSync(join(dir, 'evidence.md'), `# Evidence ${id}\n`);
    if (overrides.after) overrides.after(dir, manifest);
    return dir;
}
const run = (dir) => spawnSync('sh', [validator, repo, dir], { encoding: 'utf8' });
let failures = 0;
const check = (name, body) => {
    try { body(); console.log('PASS: ' + name); }
    catch (error) { failures++; console.error('FAIL: ' + name + ': ' + error.message); }
};

check('the validator exists', () => {
    assert.equal(existsSync(validator), true, validator + ' is missing');
});

check('an intact bundle validates and names the reviewed commit and tree', () => {
    const result = run(bundle('2026-09-15T000000Z-intact'));
    assert.equal(result.status, 0, result.stderr + result.stdout);
    assert.match(result.stdout, new RegExp(head.slice(0, 7)));
    assert.match(result.stdout, new RegExp(headTree.slice(0, 7)));
});

check('a write under an ignored path does not move the fingerprint', () => {
    mkdirSync(join(repo, '.data'), { recursive: true });
    writeFileSync(join(repo, '.data', 'generated.txt'), String(Date.now()));
    const result = run(bundle('2026-09-15T000001Z-ignored'));
    assert.equal(result.status, 0, result.stderr + result.stdout);
});

check('a source change fails on the fingerprint before anything else', () => {
    const dir = bundle('2026-09-15T000002Z-drift');
    writeFileSync(join(repo, 'plugin.php'), readFileSync(join(repo, 'plugin.php'), 'utf8') + '// changed\n');
    const result = run(dir);
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /fingerprint/i);
    git(repo, 'checkout', '--', 'plugin.php');
});

check('a missing inventory fails naming it', () => {
    const dir = bundle('2026-09-15T000003Z-missing', { after: (d) => rmSync(join(d, 'inventories', 'hooks.md')) });
    const result = run(dir);
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /hooks/);
});

check('an unknown inventory status fails', () => {
    const dir = bundle('2026-09-15T000004Z-status', { manifest: { inventories: undefined } });
    const manifest = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
    manifest.inventories = Object.fromEntries(inventories.map((n) => [statusKey(n), 'COMPLETE']));
    manifest.inventories.hooks = 'DONE';
    writeFileSync(join(dir, 'manifest.json'), JSON.stringify(manifest));
    const result = run(dir);
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /hooks.*DONE|DONE.*hooks/);
});

check('UNVERIFIED requires a stated limitation in the inventory', () => {
    const bare = bundle('2026-09-15T000005Z-unverified', { after: (d, m) => {
        m.inventories.hooks = 'UNVERIFIED';
        writeFileSync(join(d, 'manifest.json'), JSON.stringify(m));
    } });
    let result = run(bare);
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /hooks.*Limitation|Limitation.*hooks/);
    writeFileSync(join(bare, 'inventories', 'hooks.md'), '# hooks\n\nLimitation: hook callers were not traced; rerun the hooks discovery check with the retained site up.\n');
    result = run(bare);
    assert.equal(result.status, 0, result.stderr + result.stdout);
});

check('NOT_APPLICABLE requires evidence in the inventory', () => {
    const bare = bundle('2026-09-15T000006Z-na', { after: (d, m) => {
        m.inventories.money_and_authority = 'NOT_APPLICABLE';
        writeFileSync(join(d, 'manifest.json'), JSON.stringify(m));
    } });
    let result = run(bare);
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /money.and.authority/);
    writeFileSync(join(bare, 'inventories', 'money-and-authority.md'), '# money\n\nNot applicable: the plugin takes no payment and grants no capability; grep for wc_create_order and add_cap returned nothing.\n');
    result = run(bare);
    assert.equal(result.status, 0, result.stderr + result.stdout);
});

check('a bundle for a different commit fails', () => {
    const dir = bundle('2026-09-15T000007Z-commit', { manifest: { head_commit: '0'.repeat(40) } });
    const result = run(dir);
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /commit/i);
});

check('a dirty tree is reported with its changed files and the reviewed tree', () => {
    writeFileSync(join(repo, 'extra.php'), '<?php // untracked, unrelated\n');
    const dir = bundle('2026-09-15T000008Z-dirty', { manifest: { git_status: 'dirty', working_tree_changes: ['?? extra.php'] } });
    const result = run(dir);
    assert.equal(result.status, 0, result.stderr + result.stdout);
    assert.match(result.stdout, /extra\.php/);
    assert.match(result.stdout, new RegExp(headTree.slice(0, 7)));
    rmSync(join(repo, 'extra.php'));
});

check('a schema 1 bundle carrying porcelain text in git_status is read as dirty, not rejected', () => {
    writeFileSync(join(repo, 'extra.php'), '<?php // untracked\n');
    const dir = bundle('2026-09-15T000009Z-legacy', { manifest: { schema_version: 1, head_tree: undefined, working_tree_changes: undefined, git_status: '?? extra.php' } });
    const result = run(dir);
    assert.equal(result.status, 0, result.stderr + result.stdout);
    assert.match(result.stdout, /dirty/);
    assert.match(result.stdout, /extra\.php/);
    rmSync(join(repo, 'extra.php'));
});

if (failures) { console.error(failures + ' failing'); process.exit(1); }
console.log('validate-evidence: all checks pass');
