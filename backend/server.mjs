// Swat fleet backend — the shared blocklist/report store behind the
// app, backed by MongoDB Atlas ([MLH] Best Use of MongoDB Atlas).
//
//   POST /reports   file a protection report; also upserts the sender
//                   into the shared blocklist with a report counter
//   GET  /blocklist the community blocklist, riskiest first
//   GET  /reports   the latest reports
//   GET  /health    liveness + database reachability
//
// Config: MONGODB_URI (Atlas connection string), MONGODB_DB (default
// "swat"), PORT (default 8787). See README.md for the 5-minute Atlas
// free-tier setup. Deployable as-is on Vultr (see ../deploy/).

import http from 'node:http';
import { MongoClient } from 'mongodb';
import { validateReport, reportDocument } from './validate.mjs';

const uri = process.env.MONGODB_URI;
const port = Number(process.env.PORT ?? 8787);

if (!uri) {
  console.error(
    'MONGODB_URI is not set. Create a free MongoDB Atlas cluster and ' +
      'put its connection string in the environment — see backend/README.md.',
  );
  process.exit(1);
}

const client = new MongoClient(uri);
await client.connect();
const db = client.db(process.env.MONGODB_DB ?? 'swat');
const reports = db.collection('reports');
const blocklist = db.collection('blocklist');
await reports.createIndex({ incidentId: 1 }, { unique: true });
await blocklist.createIndex({ sender: 1 }, { unique: true });
console.log('Connected to MongoDB Atlas (db: %s)', db.databaseName);

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 64_000) reject(new Error('body too large'));
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    if (req.method === 'OPTIONS') return sendJson(res, 204, {});

    if (req.method === 'GET' && url.pathname === '/health') {
      await db.command({ ping: 1 });
      return sendJson(res, 200, { ok: true, mongo: true });
    }

    if (req.method === 'POST' && url.pathname === '/reports') {
      let body;
      try {
        body = JSON.parse(await readBody(req));
      } catch {
        return sendJson(res, 400, { error: 'invalid JSON body' });
      }
      const problem = validateReport(body);
      if (problem) return sendJson(res, 400, { error: problem });

      const doc = reportDocument(body);
      await reports.updateOne(
        { incidentId: doc.incidentId },
        { $set: doc },
        { upsert: true },
      );
      await blocklist.updateOne(
        { sender: doc.sender },
        {
          $inc: { reports: 1 },
          $max: { riskScore: doc.riskScore },
          $set: { lastIncidentId: doc.incidentId, updatedAt: doc.reportedAt },
          $setOnInsert: { firstSeenAt: doc.reportedAt },
        },
        { upsert: true },
      );
      return sendJson(res, 201, { stored: true, incidentId: doc.incidentId });
    }

    if (req.method === 'GET' && url.pathname === '/blocklist') {
      const rows = await blocklist
        .find({}, { projection: { _id: 0 } })
        .sort({ riskScore: -1 })
        .limit(100)
        .toArray();
      return sendJson(res, 200, { blocklist: rows });
    }

    if (req.method === 'GET' && url.pathname === '/reports') {
      const rows = await reports
        .find({}, { projection: { _id: 0 } })
        .sort({ reportedAt: -1 })
        .limit(50)
        .toArray();
      return sendJson(res, 200, { reports: rows });
    }

    return sendJson(res, 404, { error: 'not found' });
  } catch (err) {
    console.error(err);
    return sendJson(res, 500, { error: 'internal error' });
  }
});

server.listen(port, () => {
  console.log('Swat fleet backend listening on :%d', port);
});
