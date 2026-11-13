'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

const MAX_RECENT = 500;
const MAX_LOG_BYTES = 10 * 1024 * 1024;

function createSecurityLogger({ directory, hashSecret }) {
	const filePath = path.join(directory, 'security-events.jsonl');
	const recent = [];
	const listeners = new Set();
	const secret = hashSecret || 'change-this-audit-secret';
	let writeQueue = Promise.resolve();

	function hash(value) {
		return crypto.createHmac('sha256', secret).update(String(value || 'unknown')).digest('hex').slice(0, 24);
	}

	function sanitizePath(value) {
		return String(value || '/').split('?')[0].slice(0, 300);
	}

	function add(event) {
		const record = {
			id: crypto.randomUUID(),
			timestamp: new Date().toISOString(),
			...event
		};
		recent.push(record);
		while (recent.length > MAX_RECENT) recent.shift();
		for (const listener of listeners) listener(record);
		writeQueue = writeQueue.then(async () => {
			await fs.mkdir(directory, { recursive: true });
			await fs.appendFile(filePath, `${JSON.stringify(record)}\n`, 'utf8');
			const stat = await fs.stat(filePath);
			if (stat.size > MAX_LOG_BYTES) {
				const contents = await fs.readFile(filePath, 'utf8');
				const lines = contents.trim().split('\n').slice(-Math.floor(MAX_RECENT / 2));
				await fs.writeFile(filePath, `${lines.join('\n')}\n`, 'utf8');
			}
		}).catch(error => console.error('Security log write failed:', error.message));
		return record;
	}

	async function loadRecent() {
		try {
			const contents = await fs.readFile(filePath, 'utf8');
			for (const line of contents.trim().split('\n').slice(-MAX_RECENT)) {
				try {
					const record = JSON.parse(line);
					if (record && record.id) recent.push(record);
				} catch {
					console.error('Ignoring malformed security log entry.');
				}
			}
		} catch (error) {
			if (error.code !== 'ENOENT') console.error('Security log load failed:', error.message);
		}
	}

	function subscribe(listener) {
		listeners.add(listener);
		return () => listeners.delete(listener);
	}

	return {
		filePath,
		hash,
		add,
		loadRecent,
		subscribe,
		recent: () => recent.slice(-MAX_RECENT)
	};
}

module.exports = { createSecurityLogger, sanitizePath: value => String(value || '/').split('?')[0].slice(0, 300) };
