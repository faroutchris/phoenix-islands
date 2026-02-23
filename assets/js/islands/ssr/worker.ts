import components from 'virtual:components'
import { render } from 'svelte/server'

let buffer = "";

process.stdin.setEncoding("utf8");

process.stdin.on("data", (chunk: string) => {
  buffer += chunk;

  while (true) {
    const endIndex = buffer.indexOf("\n");

    if (endIndex === -1) break;

    const line = buffer.slice(0, endIndex);
    buffer = buffer.slice(endIndex + 1)

    let msgId = null;
    try {
      const message = JSON.parse(line.trim())
      msgId = message.id;

      const Component = components[message.module];

      if (!Component) {
        throw new Error(`Component not found: ${message.module}`);
      }

      // Svelte 5 SSR provides body and head as output of render
      const { body, head } = render(Component, { props: message.props || {} });

      process.stdout.write(JSON.stringify({ ok: true, id: msgId, data: { html: body, head } }) + "\n");
    } catch (error) {
      process.stdout.write(JSON.stringify({ ok: false, id: msgId, error: String(error) }) + "\n");
    }
  }
});
