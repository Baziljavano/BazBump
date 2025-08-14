const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
require('dotenv').config();

const app = express();
app.use(bodyParser.json());
app.use(express.static('public'));

const SERVERS_FILE = './servers.json';

function loadServers() {
    if (!fs.existsSync(SERVERS_FILE)) return [];
    return JSON.parse(fs.readFileSync(SERVERS_FILE));
}

function saveServers(data) {
    fs.writeFileSync(SERVERS_FILE, JSON.stringify(data, null, 2));
}

// API endpoint BazBump calls when a server bumps
app.post('/api/servers', (req, res) => {
    if (req.headers.authorization !== `Bearer ${process.env.API_KEY}`) {
        return res.status(403).json({ error: 'Unauthorized' });
    }

    const servers = loadServers();
    const idx = servers.findIndex(s => s.id === req.body.id);

    if (idx >= 0) {
        servers[idx] = req.body;
    } else {
        servers.push(req.body);
    }

    saveServers(servers);
    res.json({ success: true });
});

// API endpoint website uses to display servers
app.get('/api/servers', (req, res) => {
    res.json(loadServers());
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));