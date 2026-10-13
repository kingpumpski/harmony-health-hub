import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = 'src';
const hooks = [
  'useCallback', 'useContext', 'useDebugValue', 'useDeferredValue',
  'useEffect', 'useId', 'useImperativeHandle', 'useInsertionEffect',
  'useLayoutEffect', 'useMemo', 'useReducer', 'useRef', 'useState',
  'useSyncExternalStore', 'useTransition'
];
const extensions = new Set(['.ts', '.tsx', '.js', '.jsx']);
const ignored = new Set(['node_modules', 'dist', 'build', '.git']);
const files = [];

function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!ignored.has(entry.name)) walk(path.join(directory, entry.name));
    } else if (extensions.has(path.extname(entry.name))) {
      files.push(path.join(directory, entry.name));
    }
  }
}

walk(root);
const violations = [];

for (const file of files) {
  const source = fs.readFileSync(file, 'utf8');
  const reactImports = [...source.matchAll(/import\\s+([^;]*?)\\s+from\\s+['"]react['"];?/gs)]
    .map(match => match[1]);
  const namedImports = reactImports.flatMap(specifier => {
    const named = specifier.match(/\\{([^}]*)\\}/s)?.[1] ?? '';
    return named.split(',').map(item => item.trim().split(/\\s+as\\s+/)[0]).filter(Boolean);
  });
  const hasReactNamespace = reactImports.some(specifier => /(?:^|,|\\s)React(?:,|$|\\s)/.test(specifier) || /\\*\\s+as\\s+React/.test(specifier));

  for (const hook of hooks) {
    const bareCall = new RegExp('(?<![\\w$.])' + hook + '\\\\s*\\\\(').test(source);
    if (!bareCall) continue;
    if (namedImports.includes(hook)) continue;
    const namespaceCall = new RegExp('\\\\bReact\\\\s*\\\\.\\\\s*' + hook + '\\\\s*\\\\(').test(source);
    if (hasReactNamespace && namespaceCall) continue;
    violations.push(file + ': calls ' + hook + '() without importing it from React');
  }
}

assert.deepEqual(violations, [], 'React hook imports must be complete to prevent lazy-route runtime crashes:\\n' + violations.join('\\n'));
console.log('React hook import runtime guard passed (' + files.length + ' source files scanned).');
