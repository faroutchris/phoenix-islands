declare const process: {
  stdin: {
    setEncoding(encoding: string): void;
    on(event: string, listener: (chunk: string) => void): void;
  };
  stdout: { write(data: string): boolean };
  exitCode: number;
};

let buffer = "";

process.stdin.setEncoding("utf8");

process.stdin.on("data", (chunk: string) => {
  buffer += chunk;

  while (true) {
    const endIndex = buffer.indexOf("\n");

    if (endIndex === -1) break;

    const line = buffer.slice(0, endIndex);
    buffer = buffer.slice(endIndex + 1)

    try {
      const message = JSON.parse(line.trim())
      process.stdout.write(JSON.stringify({ok: true, id: message.id, data: message}) + "\n");
    } catch(error) {
      process.stdout.write(JSON.stringify({ok: false, id: null, error: "invalid_json"}) + "\n");
    }
  }
});
