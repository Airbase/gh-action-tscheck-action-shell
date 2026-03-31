import { spawnSync, type SpawnSyncOptionsWithStringEncoding } from 'node:child_process';
import { chmod, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');

type SetupScenario = (originPath: string, seedPath: string) => Promise<void>;
type RunOptions = Omit<SpawnSyncOptionsWithStringEncoding, 'encoding'>;

function assertStatus(expectedStatus: number, actualStatus: number, scenario: string, output: string): void {
  if (expectedStatus !== actualStatus) {
    throw new Error(
      `Scenario '${scenario}' failed: expected exit ${expectedStatus}, got ${actualStatus}.\n\n${output}`,
    );
  }
}

function run(
  command: string,
  args: string[],
  options: RunOptions = {},
): { stdout: string; stderr: string; status: number } {
  const result = spawnSync(command, args, {
    ...options,
    encoding: 'utf8',
  });

  return {
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    status: result.status ?? 1,
  };
}

function runOrThrow(command: string, args: string[], options: RunOptions = {}): string {
  const result = run(command, args, options);

  if (result.status !== 0) {
    throw new Error(
      `Command failed: ${command} ${args.join(' ')}\n\nstdout:\n${result.stdout}\n\nstderr:\n${result.stderr}`,
    );
  }

  return result.stdout;
}

function git(repoPath: string, args: string[]): string {
  return runOrThrow('git', ['-C', repoPath, ...args]);
}

async function initRepo(repoPath: string): Promise<void> {
  git(repoPath, ['config', 'user.name', 'Copilot Test']);
  git(repoPath, ['config', 'user.email', 'copilot-tests@example.com']);
}

async function writeRepoFile(repoPath: string, relativePath: string, content: string): Promise<void> {
  await mkdir(dirname(join(repoPath, relativePath)), { recursive: true });
  await writeFile(join(repoPath, relativePath), `${content}\n`);
}

async function commitAll(repoPath: string, message: string): Promise<void> {
  git(repoPath, ['add', '.']);
  git(repoPath, ['commit', '-m', message]);
}

async function setupStaleBasePass(originPath: string, seedPath: string): Promise<void> {
  git(process.cwd(), ['init', '--bare', originPath]);
  git(process.cwd(), ['clone', originPath, seedPath]);
  await initRepo(seedPath);

  await writeRepoFile(seedPath, 'src/example.ts', 'export const value = 1;');
  await commitAll(seedPath, 'initial');
  git(seedPath, ['branch', '-M', 'master']);
  git(seedPath, ['push', '-u', 'origin', 'master']);

  git(seedPath, ['checkout', '-b', 'feature']);
  await writeRepoFile(seedPath, 'src/example.ts', 'export const value = 2;');
  await commitAll(seedPath, 'feature change');
  git(seedPath, ['push', '-u', 'origin', 'feature']);

  git(seedPath, ['checkout', 'master']);
  await writeRepoFile(seedPath, 'src/base-only.ts', '// @ts-nocheck\nexport const baseOnly = true;');
  await commitAll(seedPath, 'base adds ts-nocheck');
  git(seedPath, ['push']);
}

async function setupTruePositiveFail(originPath: string, seedPath: string): Promise<void> {
  git(process.cwd(), ['init', '--bare', originPath]);
  git(process.cwd(), ['clone', originPath, seedPath]);
  await initRepo(seedPath);

  await writeRepoFile(seedPath, 'src/example.ts', 'export const value = 1;');
  await commitAll(seedPath, 'initial');
  git(seedPath, ['branch', '-M', 'master']);
  git(seedPath, ['push', '-u', 'origin', 'master']);

  git(seedPath, ['checkout', '-b', 'feature']);
  await writeRepoFile(seedPath, 'src/example.ts', '// @ts-nocheck\nexport const value = 2;');
  await commitAll(seedPath, 'feature adds ts-nocheck');
  git(seedPath, ['push', '-u', 'origin', 'feature']);
}

async function setupRemovalPass(originPath: string, seedPath: string): Promise<void> {
  git(process.cwd(), ['init', '--bare', originPath]);
  git(process.cwd(), ['clone', originPath, seedPath]);
  await initRepo(seedPath);

  await writeRepoFile(seedPath, 'src/example.ts', 'export const value = 1;');
  await commitAll(seedPath, 'initial');
  git(seedPath, ['branch', '-M', 'master']);
  git(seedPath, ['push', '-u', 'origin', 'master']);

  await writeRepoFile(seedPath, 'src/example.ts', '// @ts-nocheck\nexport const value = 1;');
  await commitAll(seedPath, 'base adds ts-nocheck');
  git(seedPath, ['push']);

  git(seedPath, ['checkout', '-b', 'feature']);
  await writeRepoFile(seedPath, 'src/example.ts', 'export const value = 1;');
  await commitAll(seedPath, 'feature removes ts-nocheck');
  git(seedPath, ['push', '-u', 'origin', 'feature']);
}

async function createCheckout(originPath: string, checkoutPath: string): Promise<void> {
  git(process.cwd(), ['clone', '--depth', '1', '--branch', 'feature', `file://${originPath}`, checkoutPath]);
  git(checkoutPath, ['checkout', '--detach', 'HEAD']);
}

async function createMockCurl(mockBinPath: string): Promise<void> {
  await mkdir(mockBinPath, { recursive: true });

  const curlScript = `#!/bin/bash
cat <<'JSON'
{"base":{"ref":"master"},"head":{"ref":"feature"}}
JSON
`;

  const curlPath = join(mockBinPath, 'curl');
  await writeFile(curlPath, curlScript);
  await chmod(curlPath, 0o755);
}

async function runScenario(scenarioName: string, expectedStatus: number, setup: SetupScenario): Promise<void> {
  const tempDir = await mkdtemp(join(tmpdir(), 'diff-test-'));
  const originPath = join(tempDir, 'origin.git');
  const seedPath = join(tempDir, 'seed');
  const checkoutPath = join(tempDir, 'checkout');
  const mockBinPath = join(tempDir, 'mock-bin');

  try {
    await setup(originPath, seedPath);
    await createCheckout(originPath, checkoutPath);
    await createMockCurl(mockBinPath);

    const result = run('bash', [join(ROOT_DIR, 'diff.sh')], {
      cwd: checkoutPath,
      env: {
        ...process.env,
        PATH: `${mockBinPath}:${process.env.PATH ?? ''}`,
        PR_NUMBER: '123',
        GITHUB_REPOSITORY: 'Airbase/gh-action-tscheck-action-shell',
        GITHUB_TOKEN: 'test-token',
      },
    });

    assertStatus(expectedStatus, result.status, scenarioName, `${result.stdout}${result.stderr}`);
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

await runScenario('stale base changes are ignored', 0, setupStaleBasePass);
await runScenario('new ts-nocheck addition fails', 1, setupTruePositiveFail);
await runScenario('ts-nocheck removal passes', 0, setupRemovalPass);

console.log('All diff.sh tests passed.');
