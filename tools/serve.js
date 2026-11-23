// Minimal static file server used only to hand local PNGs to Studio's upload_image tool.
const http = require("http"), fs = require("fs"), path = require("path");
const root = path.resolve(process.argv[2] || ".");
const port = Number(process.argv[3] || 8765);
http.createServer((req, res) => {
  const file = path.join(root, path.normalize(decodeURIComponent(req.url.split("?")[0])).replace(/^([\\/])+/, ""));
  if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "Content-Type": file.endsWith(".png") ? "image/png" : "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
}).listen(port, "127.0.0.1", () => console.log("serving", root, "on", port));
