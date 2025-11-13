const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;
const VERSION = process.env.APP_VERSION || '1.0.0';

app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: VERSION
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Welcome to SurePay API',
    version: VERSION,
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString()
  });
});

// API endpoint
app.get('/api/status', (req, res) => {
  res.json({
    service: 'SurePay',
    version: VERSION,
    status: 'operational',
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Version: ${VERSION}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

