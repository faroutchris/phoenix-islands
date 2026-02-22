const esbuild = require('esbuild');
const esbuildSvelte = require('esbuild-svelte');

const args = process.argv.slice(2);
const watch = args.includes('--watch');
const deploy = args.includes('--deploy');

const clientOpts = {
    entryPoints: ['js/app.js'],
    bundle: true,
    target: 'es2020',
    outdir: '../priv/static/assets/js',
    logLevel: 'info',
    external: ["/fonts/*", "/images/*"],
    alias: { "@": "." },
    minify: deploy,
    sourcemap: watch ? 'inline' : false,
    plugins: [
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
    target: 'es2020',
    format: 'cjs',
    outdir: '../priv/static/assets/ssr',
    logLevel: 'info',
    alias: { "@": "." },
    minify: deploy,
    sourcemap: watch ? 'inline' : false,
    plugins: [
        esbuildSvelte({
            compilerOptions: {
                dev: watch,
                css: 'injected',
                generate: 'ssr'
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