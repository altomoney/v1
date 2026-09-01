import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const directory = dirname(fileURLToPath(import.meta.url));

try {
  process.loadEnvFile(resolve(directory, "../../.env"));
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}

const jwt = process.env.PINATA_JWT?.trim();
if (!jwt) throw new Error("PINATA_JWT is required in .env or the process environment");

const html = await readFile(resolve(directory, "index.html"));
const sha256 = createHash("sha256").update(html).digest("hex");
const form = new FormData();

form.append("file", new File([html], "index.html", { type: "text/html;charset=utf-8" }));
form.append("pinataMetadata", JSON.stringify({
  name: "alto-emergency-controller",
  keyvalues: { application: "alto-emergency-controller", sha256 }
}));
form.append("pinataOptions", JSON.stringify({ cidVersion: 1, wrapWithDirectory: true }));

const response = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}` },
  body: form
});

const body = await response.json().catch(() => null);
if (!response.ok) {
  const message = body?.error?.message || body?.message || response.statusText;
  throw new Error(`Pinata upload failed (${response.status}): ${message}`);
}

const cid = body?.IpfsHash;
if (!cid) throw new Error("Pinata response did not contain a CID");

console.log("Uploaded and pinned as an IPFS website directory");
console.log(`Website CID: ${cid}`);
console.log(`Native IPFS URI: ipfs://${cid}/`);
console.log(`dweb.link URL: https://${cid}.ipfs.dweb.link/`);
console.log(`inbrowser.link URL: https://${cid}.ipfs.inbrowser.link/`);
console.log(`SHA-256: ${sha256}`);
console.log(`Pin size: ${body.PinSize} bytes`);
