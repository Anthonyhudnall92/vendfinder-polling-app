const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { Pool } = require('pg');
const Redis = require('redis');
const prometheus = require('prom-client');
const axios = require('axios');
const nodemailer = require('nodemailer');

const app = express();
const port = process.env.PORT || 3000;

// Prometheus metrics
const register = prometheus.register;
prometheus.collectDefaultMetrics({ register });

const httpRequestsTotal = new prometheus.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'status']
});

const pollSubmissionsTotal = new prometheus.Counter({
    name: 'poll_submissions_total',
    help: 'Total number of poll submissions',
    labelNames: ['status']
});

const pollInteractionsTotal = new prometheus.Counter({
    name: 'poll_interactions_total',
    help: 'Total number of user interactions',
    labelNames: ['type', 'question']
});

const responseTimeHistogram = new prometheus.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route']
});

register.registerMetric(httpRequestsTotal);
register.registerMetric(pollSubmissionsTotal);
register.registerMetric(pollInteractionsTotal);
register.registerMetric(responseTimeHistogram);

// Database connection
const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: false
});

// Redis connection
const redis = Redis.createClient({
    url: process.env.REDIS_URL
});

// Handle Redis connection errors gracefully
redis.on('error', (err) => {
    console.error('Redis connection error:', err);
});

redis.on('connect', () => {
    console.log('Connected to Redis');
});

redis.on('ready', () => {
    console.log('Redis client ready');
});

// Connect to Redis with error handling
redis.connect().catch((err) => {
    console.error('Failed to connect to Redis:', err);
});

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Rate limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
    message: 'Too many requests from this IP'
});
app.use(limiter);

// Metrics middleware
app.use((req, res, next) => {
    const start = Date.now();
    
    res.on('finish', () => {
        const duration = (Date.now() - start) / 1000;
        responseTimeHistogram
            .labels(req.method, req.route?.path || req.path)
            .observe(duration);
            
        httpRequestsTotal
            .labels(req.method, req.route?.path || req.path, res.statusCode)
            .inc();
    });
    
    next();
});

// Database initialization
async function initDatabase() {
    try {
        await pool.query(`
            CREATE TABLE IF NOT EXISTS poll_responses (
                id SERIAL PRIMARY KEY,
                session_id VARCHAR(255) UNIQUE NOT NULL,
                interest VARCHAR(50),
                use_cases TEXT[],
                frequency VARCHAR(50),
                pain_point VARCHAR(100),
                price_willing INTEGER,
                features TEXT[],
                feedback TEXT,
                notify VARCHAR(10),
                email VARCHAR(255),
                time_to_complete INTEGER,
                interaction_count INTEGER,
                user_agent TEXT,
                viewport JSONB,
                referrer TEXT,
                timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            )
        `);

        await pool.query(`
            CREATE TABLE IF NOT EXISTS poll_interactions (
                id SERIAL PRIMARY KEY,
                session_id VARCHAR(255) NOT NULL,
                timestamp BIGINT NOT NULL,
                type VARCHAR(50) NOT NULL,
                element VARCHAR(100),
                value TEXT,
                question TEXT,
                time_on_page INTEGER,
                user_agent TEXT,
                viewport JSONB,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
            )
        `);

        await pool.query(`
            CREATE INDEX IF NOT EXISTS idx_poll_responses_session_id ON poll_responses(session_id);
            CREATE INDEX IF NOT EXISTS idx_poll_responses_timestamp ON poll_responses(timestamp);
            CREATE INDEX IF NOT EXISTS idx_poll_interactions_session_id ON poll_interactions(session_id);
            CREATE INDEX IF NOT EXISTS idx_poll_interactions_timestamp ON poll_interactions(timestamp);
        `);

        console.log('Database initialized successfully');
    } catch (error) {
        console.error('Database initialization failed:', error);
    }
}

// Routes
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/ready', async (req, res) => {
    try {
        await pool.query('SELECT 1');
        // Try Redis ping but don't fail if Redis is unavailable
        try {
            await redis.ping();
        } catch (redisError) {
            console.warn('Redis not available:', redisError.message);
        }
        res.status(200).json({ status: 'ready', timestamp: new Date().toISOString() });
    } catch (error) {
        res.status(503).json({ status: 'not ready', error: error.message });
    }
});

app.get('/metrics', async (req, res) => {
    try {
        res.set('Content-Type', register.contentType);
        const metrics = await register.metrics();
        res.end(metrics);
    } catch (error) {
        console.error('Error generating metrics:', error);
        res.status(500).send('Error generating metrics');
    }
});

// Submit poll response
app.post('/api/poll/submit', async (req, res) => {
    const {
        sessionId,
        interest,
        'use-cases': useCases,
        frequency,
        'pain-point': painPoint,
        price_willing,
        features,
        feedback,
        notify,
        email,
        timeToComplete,
        interactionCount,
        userAgent,
        viewport,
        referrer
    } = req.body;

    // Generate sessionId if not provided
    const finalSessionId = sessionId || `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    try {
        // Check if response already exists
        const existing = await pool.query(
            'SELECT id FROM poll_responses WHERE session_id = $1',
            [finalSessionId]
        );

        if (existing.rows.length > 0) {
            pollSubmissionsTotal.labels('duplicate').inc();
            return res.status(409).json({ error: 'Response already submitted for this session' });
        }

        // Insert poll response
        const result = await pool.query(`
            INSERT INTO poll_responses (
                session_id, interest, use_cases, frequency, pain_point, 
                price_willing, features, feedback, notify, email,
                time_to_complete, interaction_count, user_agent, viewport, referrer
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
            RETURNING id
        `, [
            finalSessionId,
            interest,
            Array.isArray(useCases) ? useCases : [useCases].filter(Boolean),
            frequency,
            painPoint,
            parseInt(price_willing),
            Array.isArray(features) ? features : [features].filter(Boolean),
            feedback,
            notify,
            email,
            timeToComplete,
            interactionCount,
            userAgent,
            viewport,
            referrer
        ]);

        // Cache aggregated stats in Redis
        await updateAggregatedStats();

        // Send notifications for important responses
        await notifyNewSubmission({
            interest,
            priceWilling: parseInt(price_willing),
            useCases,
            email,
            timeToComplete,
            interactionCount
        });

        pollSubmissionsTotal.labels('success').inc();
        
        res.status(201).json({ 
            success: true, 
            id: result.rows[0].id,
            message: 'Poll response submitted successfully' 
        });

    } catch (error) {
        console.error('Error submitting poll:', error);
        pollSubmissionsTotal.labels('error').inc();
        res.status(500).json({ error: 'Failed to submit poll response' });
    }
});

// Track individual interactions
app.post('/api/poll/interaction', async (req, res) => {
    const {
        sessionId,
        timestamp,
        type,
        element,
        value,
        question,
        timeOnPage,
        userAgent,
        viewport
    } = req.body;

    try {
        await pool.query(`
            INSERT INTO poll_interactions (
                session_id, timestamp, type, element, value, question,
                time_on_page, user_agent, viewport
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        `, [
            sessionId,
            timestamp,
            type,
            element,
            value,
            question,
            timeOnPage,
            userAgent,
            viewport
        ]);

        pollInteractionsTotal.labels(type, question || 'unknown').inc();
        
        res.status(201).json({ success: true });

    } catch (error) {
        console.error('Error tracking interaction:', error);
        res.status(500).json({ error: 'Failed to track interaction' });
    }
});

// Batch interaction tracking
app.post('/api/poll/interactions/batch', async (req, res) => {
    const { sessionId, interactions } = req.body;

    try {
        const client = await pool.connect();
        
        try {
            await client.query('BEGIN');
            
            for (const interaction of interactions) {
                await client.query(`
                    INSERT INTO poll_interactions (
                        session_id, timestamp, type, element, value, question,
                        time_on_page, user_agent, viewport
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                `, [
                    sessionId,
                    interaction.timestamp,
                    interaction.type,
                    interaction.element,
                    interaction.value,
                    interaction.question,
                    interaction.timeOnPage,
                    interaction.userAgent,
                    interaction.viewport
                ]);

                pollInteractionsTotal.labels(interaction.type, interaction.question || 'unknown').inc();
            }
            
            await client.query('COMMIT');
            res.status(201).json({ success: true, processed: interactions.length });
            
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }

    } catch (error) {
        console.error('Error batch tracking interactions:', error);
        res.status(500).json({ error: 'Failed to batch track interactions' });
    }
});

// Analytics endpoint
app.get('/api/poll/analytics', async (req, res) => {
    try {
        // Check cache first (but don't fail if Redis is unavailable)
        let cached = null;
        try {
            cached = await redis.get('poll_analytics');
        } catch (redisError) {
            console.warn('Redis cache read failed:', redisError.message);
        }
        
        if (cached) {
            return res.json(JSON.parse(cached));
        }

        // Generate analytics
        const analytics = await generateAnalytics();
        
        // Cache for 5 minutes (but don't fail if Redis is unavailable)
        try {
            await redis.setEx('poll_analytics', 300, JSON.stringify(analytics));
        } catch (redisError) {
            console.warn('Redis cache write failed:', redisError.message);
        }
        
        res.json(analytics);

    } catch (error) {
        console.error('Error generating analytics:', error);
        res.status(500).json({ error: 'Failed to generate analytics' });
    }
});

// Notification functions
async function sendSlackNotification(message, channel = '#vendfinder-polling') {
    try {
        const webhookUrl = process.env.SLACK_WEBHOOK_URL;
        if (!webhookUrl) {
            console.warn('Slack webhook URL not configured');
            return;
        }

        console.log(`Sending Slack notification to ${channel}: ${message.substring(0, 50)}...`);
        
        const response = await axios.post(webhookUrl, {
            channel: channel,
            username: 'VendFinder Poll Bot',
            icon_emoji: ':bar_chart:',
            text: message
        });
        
        console.log(`Slack notification sent successfully to ${channel}, response: ${response.status}`);
    } catch (error) {
        console.error('Failed to send Slack notification:', error);
    }
}

async function sendEmailNotification(subject, htmlContent, to = 'devman31122@gmail.com') {
    try {
        const transporter = nodemailer.createTransport({
            service: 'gmail',
            auth: {
                user: process.env.EMAIL_USER,
                pass: process.env.EMAIL_PASSWORD
            }
        });

        await transporter.sendMail({
            from: 'VendFinder Poll System <noreply@vendfinder.com>',
            to: to,
            subject: subject,
            html: htmlContent
        });
    } catch (error) {
        console.error('Failed to send email notification:', error);
    }
}

async function notifyNewSubmission(responseData) {
    const { interest, priceWilling, useCases, email, timeToComplete, interactionCount } = responseData;
    
    // High-value user notification
    if (priceWilling > 20) {
        const message = `🎉 High-value user alert!\n` +
            `💰 Willing to pay: $${priceWilling}/month\n` +
            `⭐ Interest level: ${interest}\n` +
            `📧 Email: ${email || 'Not provided'}\n` +
            `⏱️ Completion time: ${Math.round(timeToComplete / 1000)}s\n` +
            `🔄 Interactions: ${interactionCount}`;
        
        await sendSlackNotification(message, '#general');
        
        const emailHtml = `
            <h2>🎉 High-Value User Alert</h2>
            <p>A user has expressed willingness to pay <strong>$${priceWilling}/month</strong> for the translation chat app!</p>
            <ul>
                <li><strong>Interest Level:</strong> ${interest}</li>
                <li><strong>Use Cases:</strong> ${Array.isArray(useCases) ? useCases.join(', ') : useCases}</li>
                <li><strong>Email:</strong> ${email || 'Not provided'}</li>
                <li><strong>Completion Time:</strong> ${Math.round(timeToComplete / 1000)} seconds</li>
                <li><strong>Engagement Score:</strong> ${interactionCount} interactions</li>
            </ul>
        `;
        
        await sendEmailNotification('🎉 High-Value User Alert - VendFinder Poll', emailHtml);
    }
    
    // Very interested user notification
    if (interest === 'very-interested') {
        const message = `⭐ Very interested user!\n` +
            `💰 Price point: $${priceWilling}/month\n` +
            `📧 Email: ${email || 'Not provided'}\n` +
            `🎯 Use cases: ${Array.isArray(useCases) ? useCases.join(', ') : useCases}`;
        
        await sendSlackNotification(message, '#general');
    }
    
    // Daily summary notification (stored in Redis for batching)
    try {
        const today = new Date().toISOString().split('T')[0];
        const key = `daily_submissions_${today}`;
        await redis.incr(key);
        await redis.expire(key, 86400); // 24 hours
    } catch (redisError) {
        console.warn('Redis daily stats update failed:', redisError.message);
    }
}

// Helper functions
async function updateAggregatedStats() {
    try {
        const stats = await pool.query(`
            SELECT 
                COUNT(*) as total_responses,
                AVG(time_to_complete) as avg_completion_time,
                AVG(interaction_count) as avg_interactions,
                AVG(price_willing) as avg_price_willing,
                COUNT(CASE WHEN interest = 'very-interested' THEN 1 END) as very_interested_count
            FROM poll_responses
        `);

        try {
            await redis.setEx('poll_stats', 3600, JSON.stringify(stats.rows[0]));
        } catch (redisError) {
            console.warn('Redis caching failed:', redisError.message);
        }
    } catch (error) {
        console.error('Error updating stats:', error);
    }
}

async function generateAnalytics() {
    const [responses, interactions, stats] = await Promise.all([
        pool.query(`
            SELECT interest, frequency, pain_point, price_willing, 
                   array_length(use_cases, 1) as use_case_count,
                   array_length(features, 1) as feature_count,
                   time_to_complete, interaction_count
            FROM poll_responses 
            WHERE created_at > NOW() - INTERVAL '30 days'
        `),
        pool.query(`
            SELECT type, COUNT(*) as count
            FROM poll_interactions 
            WHERE created_at > NOW() - INTERVAL '30 days'
            GROUP BY type
            ORDER BY count DESC
        `),
        pool.query(`
            SELECT 
                COUNT(*) as total_responses,
                AVG(time_to_complete) as avg_completion_time,
                AVG(interaction_count) as avg_interactions,
                AVG(price_willing) as avg_price_willing
            FROM poll_responses
            WHERE created_at > NOW() - INTERVAL '30 days'
        `)
    ]);

    return {
        totalResponses: stats.rows[0].total_responses,
        averageCompletionTime: stats.rows[0].avg_completion_time,
        averageInteractions: stats.rows[0].avg_interactions,
        averagePriceWilling: stats.rows[0].avg_price_willing,
        interactionTypes: interactions.rows,
        responseData: responses.rows
    };
}

// Start server
app.listen(port, async () => {
    await initDatabase();
    console.log(`Poll API server running on port ${port}`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
    console.log('SIGTERM received, shutting down gracefully');
    await pool.end();
    await redis.quit();
    process.exit(0);
});
