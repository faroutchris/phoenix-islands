const esbuild = require("esbuild");
const esbuildSvelte = require("esbuild-svelte");
const args = process.argv.slice(2);
const watch = args.includes('--watch');
const deploy = args.includes('--deploy');
const fs = require('fs');
const path = require('path');

const autoRegistryPlugin = (options) => ({
    name: 'auto-registry',
    setup(build) {
        build.onResolve({ filter: /^virtual:components$/ }, args => ({
            path: args.path,
            namespace: 'components-namespace'
        }));

        build.onLoad({ filter: /.*/, namespace: 'components-namespace' }, async args => {
            const componentsDir = path.join(__dirname, 'js/components');
            let files = [];

            try {
                files = fs.readdirSync(componentsDir).filter(f => f.endsWith('.svelte'));
            } catch (e) {
                // Return empty if directory doesn't exist yet
                return { contents: 'export default {};', loader: 'js' };
            }

            let contents = '';

            if (options.isSSR) {
                // Static imports for SSR
                const imports = files.map((f, i) => `import Cmp${i} from "./js/components/${f}";`).join('\n');
                const exports = files.map((f, i) => `"${f.replace('.svelte', '')}": Cmp${i}`).join(',\n');
                contents = `${imports}\nexport default {\n${exports}\n};`;
            } else {
                // Dynamic imports for CSR
                const exports = files.map(f => `"${f.replace('.svelte', '')}": () => import("./js/components/${f}")`).join(',\n');
                contents = `export default {\n${exports}\n};`;
            }

            return { contents, loader: 'js', resolveDir: __dirname };
        });
    }
});

const clientOpts = {
    entryPoints: ['js/app.ts'],
    bundle: true,
    format: 'esm',
    splitting: true,
    target: 'es2020',
    outdir: '../priv/static/assets/js',
    logLevel: 'info',
    external: ["/fonts/*", "/images/*"],
    alias: { "@": "." },
    minify: deploy,
    sourcemap: watch ? 'inline' : false,
    plugins: [
        autoRegistryPlugin({ isSSR: false }),
        esbuildSvelte({
            compilerOptions: {
                dev: watch,
                css: 'injected',
            }
        })
    ]
}

const ssrOpts = {
    entryPoints: ['js/islands/ssr/worker.ts'],
    bundle: true,
    platform: 'node',
    conditions: ['svelte'],
    target: 'es2020',
    format: 'cjs',
    outdir: '../priv/static/assets/ssr',
    logLevel: 'info',
    alias: { "@": "." },
    minify: deploy,
    sourcemap: watch ? 'inline' : false,
    plugins: [
        autoRegistryPlugin({ isSSR: true }),
        esbuildSvelte({
            compilerOptions: {
                dev: watch,
                css: 'injected',
                generate: 'server'
            }
        })
    ]
}

const build = async () => {
    if (watch) {
        const client = await esbuild.context(clientOpts);
        const ssr = await esbuild.context(ssrOpts);
        await Promise.all([client.watch(), ssr.watch()]);
        console.log('Watching for changes...');
    } else {
        await Promise.all([esbuild.build(clientOpts), esbuild.build(ssrOpts)]);
    }
}

build().catch(() => process.exit(1));