async function loadServers() {
    const container = document.getElementById('server-list');
    container.innerHTML = '<p>Loading servers...</p>';

    try {
        const res = await fetch('/api/servers');
        
        // If backend returns error status
        if (!res.ok) {
            console.warn(`Server responded with ${res.status}`);
            container.innerHTML = '<p>No servers have bumped yet.</p>';
            return;
        }

        const servers = await res.json();

        if (!Array.isArray(servers) || servers.length === 0) {
            container.innerHTML = '<p>No servers have bumped yet.</p>';
            return;
        }

        container.innerHTML = '';
        servers.forEach(server => {
            const card = document.createElement('div');
            card.className = 'server-card';
            card.innerHTML = `
                <h2>${server.name}</h2>
                <p>${server.description || 'No description available'}</p>
                <small>Last bump: ${server.lastBump ? new Date(server.lastBump).toLocaleString() : 'Unknown'}</small><br>
                <a href="${server.invite}" target="_blank">Join Server</a>
            `;
            container.appendChild(card);
        });
    } catch (err) {
        console.error('Error fetching servers:', err);
        container.innerHTML = '<p>No servers have bumped yet.</p>';
    }
}

loadServers();