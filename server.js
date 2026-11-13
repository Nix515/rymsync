'use strict';

require('dotenv').config();

const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const express = require('express');
const multer = require('multer');
const ffmpeg = require('fluent-ffmpeg');
const cors = require('cors');
const helmet = require('helmet');
const { rateLimit } = require('express-rate-limit');
const { createClient } = require('@supabase/supabase-js');
const { createSecurityLogger, sanitizePath } = require('./security-logger');

const ROOT = __dirname;
const UPLOAD_DIR = path.join(ROOT, 'uploads');
const PORT = Number(process.env.PORT || 3000);
const MAX_UPLOAD_MB = Number(process.env.MAX_UPLOAD_MB || 500);
const MAX_PROCESSED_MB = Number(process.env.MAX_PROCESSED_MB || 100);
const MAX_UPLOAD_BYTES = MAX_UPLOAD_MB * 1024 * 1024;
const MAX_PROCESSED_BYTES = MAX_PROCESSED_MB * 1024 * 1024;
const IMAGE_LIMIT_BYTES = 10 * 1024 * 1024;
const BUCKET = 'media';
const SUPABASE_URL = process.env.SUPABASE_URL;
const ADMIN_USER_IDS = new Set((process.env.ADMIN_USER_IDS || '').split(',').map(value => value.trim()).filter(Boolean));
const AUDIT_LOG_DIR = path.resolve(process.env.AUDIT_LOG_DIR || path.join(ROOT, 'logs'));

if (!SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
	console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in the server environment.');
	process.exit(1);
}
if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535 ||
	!Number.isFinite(MAX_UPLOAD_MB) || MAX_UPLOAD_MB <= 0 ||
	!Number.isFinite(MAX_PROCESSED_MB) || MAX_PROCESSED_MB <= 0) {
	console.error('PORT, MAX_UPLOAD_MB, and MAX_PROCESSED_MB must be valid positive numbers.');
	process.exit(1);
}

try {
	if (!['https:', 'http:'].includes(new URL(SUPABASE_URL).protocol)) throw new Error();
} catch {
	console.error('SUPABASE_URL must be a valid HTTP or HTTPS URL.');
	process.exit(1);
}

if (process.env.FFMPEG_PATH) ffmpeg.setFfmpegPath(process.env.FFMPEG_PATH);
if (process.env.FFPROBE_PATH) ffmpeg.setFfprobePath(process.env.FFPROBE_PATH);

const supabase = createClient(SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
	auth: { autoRefreshToken: false, persistSession: false }
});
const app = express();
const supabaseOrigin = new URL(SUPABASE_URL).origin;
const allowedOrigins = (process.env.WEB_ORIGIN || `http://localhost:${PORT}`)
	.split(',')
	.map(origin => origin.trim())
	.filter(Boolean);
const securityLogger = createSecurityLogger({
	directory: AUDIT_LOG_DIR,
	hashSecret: process.env.AUDIT_HASH_SECRET || process.env.SUPABASE_SERVICE_ROLE_KEY
});

app.disable('x-powered-by');
app.set('json escape', true);
app.use(helmet({
	contentSecurityPolicy: {
		directives: {
			defaultSrc: ["'self'"],
			connectSrc: ["'self'", supabaseOrigin, 'https://*.supabase.co', 'https://www.google-analytics.com', 'https://analytics.google.com', 'https://region1.google-analytics.com'],
			fontSrc: ["'self'", 'https://fonts.gstatic.com'],
			imgSrc: ["'self'", 'data:', 'blob:', 'https://images.unsplash.com', supabaseOrigin, 'https://*.supabase.co', 'https://www.google-analytics.com'],
			mediaSrc: ["'self'", 'blob:', supabaseOrigin, 'https://*.supabase.co'],
			objectSrc: ["'none'"],
			scriptSrc: ["'self'", "'unsafe-inline'", 'https://cdn.jsdelivr.net', 'https://www.googletagmanager.com'],
			styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
			baseUri: ["'self'"],
			frameAncestors: ["'none'"]
		}
	},
	crossOriginResourcePolicy: { policy: 'cross-origin' }
}));
app.use(cors({
	origin(origin, callback) {
		if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
		return callback(new Error('Origin is not allowed by CORS.'));
	}
}));
app.use(express.json({ limit: '32kb' }));
app.use(rateLimit({
	windowMs: 15 * 60 * 1000,
	limit: 600,
	standardHeaders: 'draft-8',
	legacyHeaders: false,
	message: { error: { code: 'REQUEST_RATE_LIMIT', message: 'Too many requests. Please try again later.' } }
}));
app.use((req, res, next) => {
	const startedAt = Date.now();
	res.on('finish', () => {
		const status = res.statusCode;
		securityLogger.add({
			event: status === 401 || status === 403 ? 'auth_denied' : status === 429 ? 'rate_limited' : status >= 500 ? 'server_error' : 'request',
			method: req.method,
			path: sanitizePath(req.originalUrl),
			status,
			duration_ms: Date.now() - startedAt,
			ip_hash: securityLogger.hash(req.ip),
			user_agent: String(req.get('user-agent') || 'unknown').slice(0, 180)
		});
	});
	next();
});

const storage = multer.diskStorage({
	destination: async (_req, _file, callback) => {
		try {
			await fs.mkdir(UPLOAD_DIR, { recursive: true });
			callback(null, UPLOAD_DIR);
		} catch (error) {
			callback(error);
		}
	},
	filename: (_req, file, callback) => {
		const extension = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '').slice(0, 12);
		callback(null, `${crypto.randomUUID()}${extension}`);
	}
});

const upload = multer({
	storage,
	limits: { fileSize: MAX_UPLOAD_BYTES, files: 2, fields: 4, fieldSize: 1024 },
	fileFilter(_req, file, callback) {
		const audio = file.fieldname === 'media' && /^audio\//i.test(file.mimetype);
		const image = (file.fieldname === 'media' || file.fieldname === 'cover') &&
			/^image\/(jpeg|png|webp|avif)$/i.test(file.mimetype);
		const error = audio || image ? null : Object.assign(
			new Error('Only audio files and JPEG, PNG, WebP, or AVIF images are accepted.'),
			{ status: 400, code: 'UNSUPPORTED_FILE_TYPE' }
		);
		callback(error, audio || image);
	}
});

const uploadLimiter = rateLimit({
	windowMs: 15 * 60 * 1000,
	limit: 12,
	standardHeaders: 'draft-8',
	legacyHeaders: false,
	message: { error: { code: 'UPLOAD_RATE_LIMIT', message: 'Too many uploads. Please try again later.' } }
});

async function requireProfile(req, res, next) {
	const match = (req.get('authorization') || '').match(/^Bearer\s+(.+)$/i);
	if (!match) return res.status(401).json({ error: { code: 'AUTH_REQUIRED', message: 'Sign in to publish or manage content.' } });

	try {
		const { data, error } = await supabase.auth.getUser(match[1]);
		if (error || !data.user || data.user.is_anonymous) {
			return res.status(401).json({ error: { code: 'ACCOUNT_REQUIRED', message: 'Use a registered RhythmSync account to publish content.' } });
		}
		const { data: profile, error: profileError } = await supabase
			.from('profiles')
			.select('id, role, user_id')
			.eq('user_id', data.user.id)
			.maybeSingle();
		if (profileError) throw profileError;
		if (!profile) return res.status(403).json({ error: { code: 'PROFILE_REQUIRED', message: 'Your account profile is not ready yet.' } });
		req.user = data.user;
		req.profile = profile;
		return next();
	} catch (error) {
		console.error('Upload authentication failed:', error.message);
		return res.status(503).json({ error: { code: 'AUTH_SERVICE_UNAVAILABLE', message: 'Could not verify your account. Please try again.' } });
	}
}

function probeAudio(filePath) {
	return new Promise((resolve, reject) => {
		ffmpeg.ffprobe(filePath, (error, metadata) => {
			if (error) return reject(new Error('The uploaded audio could not be decoded. Check that it is a valid audio file.'));
			resolve(metadata);
		});
	});
}

function validateAudioDuration(seconds, type) {
	const limits = type === 'track' ? { min: 30, max: 360, label: 'Music tracks' } : { min: 10, max: 60, label: 'Freestyles' };
	if (!Number.isFinite(seconds)) {
		throw Object.assign(new Error('Audio duration could not be verified. Choose a valid audio file and try again.'), { status: 400, code: 'INVALID_AUDIO_DURATION' });
	}
	if (seconds < limits.min) {
		throw Object.assign(new Error(`${limits.label} must be at least ${limits.min} seconds long. This file is too short.`), { status: 400, code: 'AUDIO_TOO_SHORT' });
	}
	if (seconds > limits.max) {
		throw Object.assign(new Error(`${limits.label} cannot be longer than ${limits.max} seconds. This file is too long.`), { status: 400, code: 'AUDIO_TOO_LONG' });
	}
}

function transcodeAudio(inputPath, outputPath) {
	return new Promise((resolve, reject) => {
		ffmpeg(inputPath)
			.noVideo()
			.audioCodec('aac')
			.audioBitrate('192k')
			.outputOptions(['-map 0:a:0', '-movflags +faststart'])
			.output(outputPath)
			.on('end', resolve)
			.on('error', error => reject(new Error(`Audio conversion failed: ${error.message}`)))
			.run();
	});
}

function cleanText(value, field, maxLength, required = false) {
	const text = typeof value === 'string' ? value.trim() : '';
	if (required && !text) throw Object.assign(new Error(`${field} is required.`), { status: 400, code: 'INVALID_METADATA' });
	if (text.length > maxLength) throw Object.assign(new Error(`${field} must be ${maxLength} characters or fewer.`), { status: 400, code: 'INVALID_METADATA' });
	return text;
}

function publicUrlFor(objectPath) {
	return supabase.storage.from(BUCKET).getPublicUrl(objectPath).data.publicUrl;
}

async function removeLocalFiles(files) {
	for (const file of files) {
		if (!file) continue;
		try {
			await fs.unlink(file);
		} catch (error) {
			if (error.code !== 'ENOENT') console.error('Temporary file cleanup failed:', error.message);
		}
	}
}

async function storeObject(objectPath, file, contentType) {
	const bytes = await fs.readFile(file.path);
	const { error } = await supabase.storage.from(BUCKET).upload(objectPath, bytes, {
		upsert: false,
		contentType,
		cacheControl: '31536000'
	});
	if (error) throw error;
	return publicUrlFor(objectPath);
}

app.get(['/','/mine.html'], (_req, res) => res.sendFile(path.join(ROOT, 'mine.html')));
app.get('/admin.html', (_req, res) => res.sendFile(path.join(ROOT, 'admin.html')));
app.get('/terms.html', (_req, res) => res.sendFile(path.join(ROOT, 'terms.html')));
app.get('/api/health', (_req, res) => res.json({ status: 'ok', service: 'RhythmSync media API' }));

async function requireAdmin(req, res, next) {
	const token = (req.get('authorization') || '').match(/^Bearer\s+(.+)$/i)?.[1];
	if (!token) return res.status(401).json({ error: { code: 'ADMIN_AUTH_REQUIRED', message: 'Administrator authentication is required.' } });
	try {
		const { data, error } = await supabase.auth.getUser(token);
		if (error || !data.user || !ADMIN_USER_IDS.has(data.user.id)) {
			securityLogger.add({ event: 'admin_access_denied', method: req.method, path: sanitizePath(req.originalUrl), status: 403, ip_hash: securityLogger.hash(req.ip) });
			return res.status(403).json({ error: { code: 'ADMIN_REQUIRED', message: 'This account is not authorized to view security events.' } });
		}
		req.adminUser = data.user;
		return next();
	} catch (error) {
		console.error('Admin authentication failed:', error.message);
		return res.status(503).json({ error: { code: 'AUTH_SERVICE_UNAVAILABLE', message: 'Could not verify administrator access.' } });
	}
}

app.get('/api/admin/logs', requireAdmin, (req, res) => {
	const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 100, 1), 500);
	return res.json({ data: securityLogger.recent().slice(-limit) });
});

app.get('/api/admin/logs/stream', requireAdmin, (req, res) => {
	res.set({
		'Content-Type': 'text/event-stream',
		'Cache-Control': 'no-cache, no-transform',
		Connection: 'keep-alive',
		'X-Accel-Buffering': 'no'
	});
	res.flushHeaders();
	res.write(': connected\n\n');
	const unsubscribe = securityLogger.subscribe(record => res.write(`data: ${JSON.stringify(record)}\n\n`));
	const heartbeat = setInterval(() => res.write(': heartbeat\n\n'), 15000);
	req.on('close', () => {
		clearInterval(heartbeat);
		unsubscribe();
		res.end();
	});
});

app.post('/api/media/upload', uploadLimiter, requireProfile, (req, res, next) => {
	upload.fields([{ name: 'media', maxCount: 1 }, { name: 'cover', maxCount: 1 }])(req, res, error => {
		if (error) return next(error);
		return handleMediaUpload(req, res, next);
	});
});

async function handleMediaUpload(req, res, next) {
	const localFiles = [];
	const cloudPaths = [];
	try {
		const media = req.files?.media?.[0];
		const cover = req.files?.cover?.[0];
		if (media) localFiles.push(media.path);
		if (cover) localFiles.push(cover.path);
		if (!media) throw Object.assign(new Error('Choose an audio file or image to upload.'), { status: 400, code: 'MEDIA_REQUIRED' });

		const type = req.body.mediaType;
		if (!['track', 'freestyle', 'post', 'profile_image'].includes(type)) {
			throw Object.assign(new Error('Choose track, freestyle, post, or profile_image. Video uploads are disabled.'), { status: 400, code: 'INVALID_MEDIA_TYPE' });
		}
		const isImage = type === 'post' || type === 'profile_image';
		const isTrack = type === 'track';
		if ((isImage && !media.mimetype.startsWith('image/')) || (!isImage && !media.mimetype.startsWith('audio/'))) {
			throw Object.assign(new Error(isImage ? 'This content type accepts images only.' : 'Tracks and freestyles accept audio files only.'), { status: 400, code: 'MEDIA_TYPE_MISMATCH' });
		}
		if (isTrack && req.profile.role !== 'musician') {
			throw Object.assign(new Error('Only musician accounts can publish music tracks.'), { status: 403, code: 'MUSICIAN_REQUIRED' });
		}
		if (isImage && media.size > IMAGE_LIMIT_BYTES) {
			throw Object.assign(new Error('Optimized images must be 10 MB or smaller.'), { status: 413, code: 'IMAGE_TOO_LARGE' });
		}
		if (cover && (!isTrack || !cover.mimetype.startsWith('image/'))) {
			throw Object.assign(new Error('Track artwork is accepted only with an audio track.'), { status: 400, code: 'INVALID_COVER' });
		}
		if (isTrack && !cover) {
			throw Object.assign(new Error('Music tracks require cover artwork.'), { status: 400, code: 'COVER_REQUIRED' });
		}
		if (cover && cover.size > IMAGE_LIMIT_BYTES) {
			throw Object.assign(new Error('Track artwork must be 10 MB or smaller.'), { status: 413, code: 'COVER_TOO_LARGE' });
		}

		if (type === 'profile_image') {
			const extension = media.mimetype.split('/')[1].replace('jpeg', 'jpg');
			const objectPath = `${req.profile.id}/profile/${crypto.randomUUID()}.${extension}`;
			cloudPaths.push(objectPath);
			const publicUrl = await storeObject(objectPath, media, media.mimetype);
			const { error } = await supabase.from('profiles').update({ avatar_url: publicUrl }).eq('id', req.profile.id);
			if (error) throw error;
			cloudPaths.length = 0;
			return res.status(201).json({ data: { publicUrl, storagePath: objectPath } });
		}

		const title = cleanText(req.body.title, 'Title', 100, true);
		const genre = cleanText(req.body.genre, 'Genre', 40);
		const description = cleanText(req.body.description, 'Description', 500);
		let mediaUrl = '';
		let mediaPath = '';
		let processedSize = media.size;
		let contentType = media.mimetype;
		let audioDuration = null;

		if (isImage) {
			const extension = media.mimetype.split('/')[1].replace('jpeg', 'jpg');
			mediaPath = `${req.profile.id}/posts/${crypto.randomUUID()}.${extension}`;
			cloudPaths.push(mediaPath);
			mediaUrl = await storeObject(mediaPath, media, media.mimetype);
		} else {
			const metadata = await probeAudio(media.path);
			if (!metadata.streams?.some(stream => stream.codec_type === 'audio')) {
				throw Object.assign(new Error('The uploaded file does not contain a valid audio stream.'), { status: 400, code: 'INVALID_MEDIA' });
			}
			const sourceAudio = metadata.streams.find(stream => stream.codec_type === 'audio');
			validateAudioDuration(Number(metadata.format?.duration ?? sourceAudio.duration), type);
			const convertedPath = path.join(UPLOAD_DIR, `${crypto.randomUUID()}.m4a`);
			localFiles.push(convertedPath);
			await transcodeAudio(media.path, convertedPath);
			const convertedMetadata = await probeAudio(convertedPath);
			const convertedAudio = convertedMetadata.streams?.find(stream => stream.codec_type === 'audio');
			audioDuration = Number(convertedMetadata.format?.duration ?? convertedAudio?.duration);
			validateAudioDuration(audioDuration, type);
			processedSize = (await fs.stat(convertedPath)).size;
			if (processedSize > MAX_PROCESSED_BYTES) {
				throw Object.assign(new Error(`The optimized audio exceeds the ${MAX_PROCESSED_MB} MB storage limit. Choose a shorter or smaller source.`), { status: 413, code: 'PROCESSED_FILE_TOO_LARGE' });
			}
			contentType = 'audio/mp4';
			mediaPath = `${req.profile.id}/${type === 'track' ? 'audio' : 'freestyles'}/${crypto.randomUUID()}.m4a`;
			cloudPaths.push(mediaPath);
			const { error } = await supabase.storage.from(BUCKET).upload(mediaPath, await fs.readFile(convertedPath), {
				upsert: false,
				contentType,
				cacheControl: '31536000'
			});
			if (error) throw error;
			mediaUrl = publicUrlFor(mediaPath);
		}

		let coverUrl = '';
		if (cover) {
			const extension = cover.mimetype.split('/')[1].replace('jpeg', 'jpg');
			const coverPath = `${req.profile.id}/covers/${crypto.randomUUID()}.${extension}`;
			cloudPaths.push(coverPath);
			coverUrl = await storeObject(coverPath, cover, cover.mimetype);
		}

		const record = isTrack
			? { artist_id: req.profile.id, title, genre, description, audio_url: mediaUrl, cover_url: coverUrl, duration_seconds: audioDuration, storage_path: mediaPath, file_size: processedSize, mime_type: contentType }
			: isImage
				? { author_id: req.profile.id, title, description, image_url: mediaUrl, storage_path: mediaPath, file_size: processedSize, mime_type: contentType }
				: { author_id: req.profile.id, title, genre, description, audio_url: mediaUrl, duration_seconds: audioDuration, storage_path: mediaPath, file_size: processedSize, mime_type: contentType };
		const table = isTrack ? 'tracks' : isImage ? 'posts' : 'freestyles';
		const { data: release, error: insertError } = await supabase.from(table).insert(record).select().single();
		if (insertError) throw insertError;
		cloudPaths.length = 0;
		return res.status(201).json({
			data: { release, publicUrl: mediaUrl, storagePath: mediaPath, originalSize: media.size, storedSize: processedSize, contentType }
		});
	} catch (error) {
		console.error('Media upload failed:', error.message);
		if (cloudPaths.length) {
			const { error: storageError } = await supabase.storage.from(BUCKET).remove(cloudPaths);
			if (storageError) console.error('Cloud media cleanup failed:', storageError.message);
		}
		return next(error);
	} finally {
		await removeLocalFiles(localFiles);
	}
}

app.delete('/api/media/:type/:id', requireProfile, async (req, res, next) => {
	const tables = {
		track: { name: 'tracks', owner: 'artist_id', fields: 'storage_path,cover_url' },
		post: { name: 'posts', owner: 'author_id', fields: 'storage_path' },
		freestyle: { name: 'freestyles', owner: 'author_id', fields: 'storage_path' }
	};
	const config = tables[req.params.type];
	if (!config) return res.status(400).json({ error: { code: 'INVALID_CONTENT_TYPE', message: 'Only tracks, image posts, and freestyles can be deleted.' } });

	try {
		if (req.params.type === 'track' && req.profile.role !== 'musician') {
			return res.status(403).json({ error: { code: 'MUSICIAN_REQUIRED', message: 'Only musicians can manage tracks.' } });
		}
		const { data: record, error: readError } = await supabase.from(config.name).select(config.fields)
			.eq('id', req.params.id).eq(config.owner, req.profile.id).maybeSingle();
		if (readError) throw readError;
		if (!record) return res.status(404).json({ error: { code: 'CONTENT_NOT_FOUND', message: 'That item was not found in your account.' } });
		const { error: deleteError } = await supabase.from(config.name).delete().eq('id', req.params.id).eq(config.owner, req.profile.id);
		if (deleteError) throw deleteError;
		const paths = [record.storage_path];
		if (record.cover_url) {
			const prefix = '/storage/v1/object/public/media/';
			const pathname = new URL(record.cover_url).pathname;
			if (pathname.startsWith(prefix)) paths.push(decodeURIComponent(pathname.slice(prefix.length)));
		}
		const { error: cleanupError } = await supabase.storage.from(BUCKET).remove(paths.filter(Boolean));
		if (cleanupError) console.error('Deleted content storage cleanup failed:', cleanupError.message);
		return res.json({ data: { deleted: true, storageCleaned: !cleanupError } });
	} catch (error) {
		return next(error);
	}
});

app.use((error, _req, res, _next) => {
	if (res.headersSent) return;
	if (error instanceof multer.MulterError) {
		const status = error.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
		const message = error.code === 'LIMIT_FILE_SIZE' ? `Uploads must be ${MAX_UPLOAD_MB} MB or smaller.` : error.message;
		return res.status(status).json({ error: { code: error.code, message } });
	}
	if (error.message === 'Origin is not allowed by CORS.') {
		return res.status(403).json({ error: { code: 'ORIGIN_NOT_ALLOWED', message: error.message } });
	}
	const status = Number.isInteger(error.status) ? error.status : 500;
	if (status >= 500) console.error('Request failed:', error.message);
	return res.status(status).json({
		error: {
			code: error.code || 'UPLOAD_FAILED',
			message: status >= 500 ? 'Upload failed while processing or saving the release. Please try again.' : error.message
		}
	});
});

securityLogger.loadRecent().finally(() => {
	app.listen(PORT, () => {
		console.log(`RhythmSync is listening on http://localhost:${PORT}`);
		if (!ADMIN_USER_IDS.size) console.warn('ADMIN_USER_IDS is not configured; the security console is disabled.');
	});
});
