// Validate an evidence bundle against the repository in front of you.
//
// A specialist review that starts on a bundle which no longer describes the source is
// reviewing something else. This recomputes the source fingerprint, checks the commit,
// checks every required inventory and the status the manifest claims for it, and reports the
// working-tree state so a reader can tell "commit X plus these uncommitted files".
//
// Exit 0 only when everything holds; otherwise one line per problem and exit 1.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const [repoArg, bundleArg] = process.argv.slice(2);
if (!repoArg || !bundleArg) {
    console.error('Usage: validate-evidence.sh <plugin-repository> <evidence-directory>');
    process.exit(2);
}
const here = dirname(fileURLToPath(import.meta.url));
const git = (...args) => execFileSync('git', ['-C', repoArg, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const repo = git('rev-parse', '--show-toplevel');
const bundle = resolve(bundleArg);
const problems = [];
const note = (line) => console.log(line);

const REQUIRED = ['files', 'feature-surfaces', 'entry-points', 'inputs-and-sinks', 'hooks', 'state-changes', 'outputs', 'bootstrap-contexts', 'dependencies-and-network', 'money-and-authority'];
const STATUSES = ['COMPLETE', 'UNVERIFIED', 'NOT_APPLICABLE'];

let manifest = null;
const manifestPath = join(bundle, 'manifest.json');
if (!existsSync(manifestPath)) {
    problems.push(`manifest.json is missing from ${bundle}`);
} else {
    try {
        manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    } catch (error) {
        problems.push(`manifest.json does not parse: ${error.message}`);
    }
}

if (manifest) {
    if (![1, 2].includes(Number(manifest.schema_version))) {
        problems.push(`schema_version ${JSON.stringify(manifest.schema_version)} is not 1 or 2`);
    }
    if (manifest.evidence_id !== basename(bundle)) {
        problems.push(`evidence_id ${JSON.stringify(manifest.evidence_id)} does not match the directory name ${basename(bundle)}`);
    }

    // 1. The source in front of us is the source the bundle indexed.
    const fingerprint = execFileSync('sh', [join(here, 'source-fingerprint.sh'), repo], { encoding: 'utf8' }).trim();
    if (fingerprint !== manifest.source_fingerprint) {
        problems.push(`source fingerprint drifted: bundle ${String(manifest.source_fingerprint).slice(0, 12)}, working tree ${fingerprint.slice(0, 12)}. Build a new bundle; do not update this one.`);
    }
    const head = git('rev-parse', 'HEAD');
    if (manifest.head_commit !== head) {
        problems.push(`head commit differs: bundle ${String(manifest.head_commit).slice(0, 12)}, repository ${head.slice(0, 12)}`);
    }

    // 2. Working-tree state, reported so the reviewed commit and unrelated changes are distinct.
    const headTree = git('rev-parse', 'HEAD^{tree}');
    const porcelain = git('status', '--porcelain');
    const currentChanges = porcelain ? porcelain.split('\n') : [];
    let recordedStatus = manifest.git_status;
    let recordedChanges = Array.isArray(manifest.working_tree_changes) ? manifest.working_tree_changes : [];
    if (recordedStatus !== 'clean' && recordedStatus !== 'dirty') {
        // Schema 1 bundles sometimes carry the porcelain text itself in git_status.
        const lines = String(recordedStatus || '').split('\n').map((l) => l.trimEnd()).filter(Boolean);
        recordedStatus = lines.length ? 'dirty' : 'clean';
        if (!recordedChanges.length) recordedChanges = lines;
    }
    if (manifest.head_tree && manifest.head_tree !== headTree) {
        problems.push(`head tree differs: bundle ${String(manifest.head_tree).slice(0, 12)}, repository ${headTree.slice(0, 12)}`);
    }
    note(`reviewed commit ${head.slice(0, 12)} (tree ${headTree.slice(0, 12)}), working tree ${recordedStatus}`);
    const changes = recordedChanges.length ? recordedChanges : currentChanges;
    if (changes.length) {
        note('working-tree changes present when the bundle was built (not part of the reviewed commit):');
        for (const line of changes) note('  ' + line);
    }

    // 3. Every required inventory is present and its declared status is backed by its content.
    const statuses = manifest.inventories && typeof manifest.inventories === 'object' ? manifest.inventories : {};
    for (const name of REQUIRED) {
        const key = name.replaceAll('-', '_');
        const file = join(bundle, 'inventories', name + '.md');
        const status = statuses[key];
        if (!existsSync(file)) {
            problems.push(`inventory ${name} is missing (${file})`);
            continue;
        }
        if (!STATUSES.includes(status)) {
            problems.push(`inventory ${name} has status ${JSON.stringify(status)}; expected one of ${STATUSES.join(', ')}`);
            continue;
        }
        const body = readFileSync(file, 'utf8');
        if (status === 'UNVERIFIED' && !/^Limitation:\s*\S/m.test(body)) {
            problems.push(`inventory ${name} is UNVERIFIED but states no "Limitation:" line saying what is unverified and how to reproduce the check`);
        }
        if (status === 'NOT_APPLICABLE' && !/^Not applicable:\s*\S/m.test(body)) {
            problems.push(`inventory ${name} is NOT_APPLICABLE but gives no "Not applicable:" line with the evidence`);
        }
    }
    const verified = REQUIRED.filter((n) => statuses[n.replaceAll('-', '_')] === 'COMPLETE').length;
    note(`inventories declared: ${verified} complete, ${REQUIRED.filter((n) => statuses[n.replaceAll('-', '_')] === 'UNVERIFIED').length} unverified, ${REQUIRED.filter((n) => statuses[n.replaceAll('-', '_')] === 'NOT_APPLICABLE').length} not applicable (declarations are checked against inventory content above)`);
}

if (problems.length) {
    for (const problem of problems) console.error('PROBLEM: ' + problem);
    console.error(`${problems.length} problem(s): do not start a specialist pass on ${basename(bundle)}`);
    process.exit(1);
}
note(`valid: ${basename(bundle)} describes the current source`);
