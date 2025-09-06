const express = require("express");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 3000;

const COLOR = process.env.APP_COLOR || "unknown";
const VERSION = process.env.APP_VERSION || "0.0.0";

app.get("/", (req, res) => {
  res.json({
    message: `Hello from ${COLOR} environment`,
    color: COLOR,
    version: VERSION,
    host: os.hostname(),
    pid: process.pid,
    time: new Date().toISOString(),
  });
});

app.get("/health", (req, res) => res.status(200).send("OK"));

app.listen(PORT, () => {
  console.log(`App ${COLOR} v${VERSION} listening on port ${PORT}`);
});