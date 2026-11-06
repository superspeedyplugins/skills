// prepare-storage.sh puts evidence in <repo>/.code-reviews (or a store outside the repository),
// keeps it out of Git without touching the tracked .gitignore, and refuses to replace anything
// it did not create. Each behaviour is proved here against temporary repositories.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const helper = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'scripts', 'prepare-storage.sh');
const root = mkdtempSync(join(tmpdir(), 'review-storage-test-'));
const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const run = (repo, env = {}) => spawnSync('sh', [helper, repo], { encoding: 'utf8', env: { ...process.env, PLUGIN_REVIEW_STORE: '', ...env } });
let failures = 0;
const check = (name, fn) => { try { fn(); console.log('PASS: ' + name); } catch (e) { failures++; console.log('FAIL: ' + name + '\n  ' + e.message); } };

function repo(name) {
    const dir = join(root, 'workspace with spaces', name);
    mkdirSync(dir, { recursive: true });
    git(dir, 'init', '-q');
    writeFileSync(join(dir, '.gitignore'), '/vendor\n');
    writeFileSync(join(dir, 'plugin.php'), '<?php\n/* Plugin Name: Sample */\n');
    git(dir, 'add', '-A');
    git(dir, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'fixture');
    return dir;
}

check('default storage is a real folder inside the repository, ignored locally', () => {
    const r = repo('in-repo');
    const result = run(r);
    assert.equal(result.status, 0, result.stderr);
    assert.ok(lstatSync(join(r, '.code-reviews')).isDirectory());
    assert.ok(existsSync(join(r, '.code-reviews', 'evidence')) && existsSync(join(r, '.code-reviews', 'reviews')));
    // Git does not show empty folders, so put a report in before asking it.
    writeFileSync(join(r, '.code-reviews', 'reviews', 'report.md'), 'report');
    assert.equal(git(r, 'status', '--porcelain', '--untracked-files=all'), '', 'nothing new for Git to see');
    assert.equal(readFileSync(join(r, '.gitignore'), 'utf8'), '/vendor\n', 'tracked .gitignore untouched');
});

check('running twice is idempotent and adds the exclude line once', () => {
    const r = join(root, 'workspace with spaces', 'in-repo');
    writeFileSync(join(r, '.code-reviews', 'evidence', 'keep.txt'), 'evidence');
    assert.equal(run(r).status, 0);
    assert.equal(readFileSync(join(r, '.code-reviews', 'evidence', 'keep.txt'), 'utf8'), 'evidence');
    const exclude = readFileSync(join(r, '.git', 'info', 'exclude'), 'utf8');
    assert.equal(exclude.split('\n').filter((l) => l === '/.code-reviews').length, 1);
});

check('PLUGIN_REVIEW_STORE keeps evidence outside the repository behind a symlink', () => {
    const r = repo('external');
    const store = join(root, 'review store');
    const result = run(r, { PLUGIN_REVIEW_STORE: store });
    assert.equal(result.status, 0, result.stderr);
    assert.ok(lstatSync(join(r, '.code-reviews')).isSymbolicLink());
    assert.equal(realpathSync(join(r, '.code-reviews')), realpathSync(join(store, 'external', '.code-reviews')));
    assert.equal(git(r, 'status', '--porcelain'), '');
    assert.equal(run(r, { PLUGIN_REVIEW_STORE: store }).status, 0, 'idempotent');
});

check('refuses a symlink that points somewhere else', () => {
    const r = repo('wrong-link');
    mkdirSync(join(root, 'elsewhere'));
    symlinkSync(join(root, 'elsewhere'), join(r, '.code-reviews'));
    assert.notEqual(run(r, { PLUGIN_REVIEW_STORE: join(root, 'review store') }).status, 0);
    assert.notEqual(run(r).status, 0, 'and without a store');
});

check('refuses to replace a real folder with a store symlink', () => {
    const r = repo('real-folder');
    mkdirSync(join(r, '.code-reviews'));
    writeFileSync(join(r, '.code-reviews', 'old-report.md'), 'old');
    assert.notEqual(run(r, { PLUGIN_REVIEW_STORE: join(root, 'review store') }).status, 0);
    assert.equal(readFileSync(join(r, '.code-reviews', 'old-report.md'), 'utf8'), 'old');
});

check('works from a linked worktree', () => {
    const r = repo('main-checkout');
    const wt = join(root, 'feature-checkout');
    git(r, 'worktree', 'add', '-q', '-b', 'feature', wt);
    const result = run(wt);
    assert.equal(result.status, 0, result.stderr);
    assert.ok(lstatSync(join(wt, '.code-reviews')).isDirectory());
    assert.equal(git(wt, 'status', '--porcelain'), '');
});

console.log(failures ? `prepare-storage: ${failures} failed` : 'prepare-storage: all checks pass');
process.exit(failures ? 1 : 0);
