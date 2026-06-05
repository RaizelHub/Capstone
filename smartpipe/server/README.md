# SmartPipe Email Server

This is a Node.js server that handles email notifications for the SmartPipe water management system.

## Setup Instructions

### 1. Install Dependencies

```bash
cd server
npm install
```

### 2. Configure Environment Variables

Create a `.env` file in the server directory with the following variables:

```env
# Email Server Configuration
PORT=3000

# Email Configuration (Gmail)
EMAIL_USER=your-email@gmail.com
EMAIL_PASSWORD=your-app-password
```

### 3. Gmail Setup (Recommended)

1. **Enable 2-Factor Authentication**:

   - Go to your Google Account settings
   - Enable 2-factor authentication

2. **Generate App Password**:

   - Go to Google Account → Security → App passwords
   - Generate a new app password for "Mail"
   - Use this password in your `.env` file

3. **Alternative Email Services**:
   - **Outlook/Hotmail**: Use your regular password
   - **Yahoo**: Enable 2FA and generate app password

### 4. Start the Server

```bash
# Development mode (with auto-restart)
npm run dev

# Production mode
npm start
```

### 5. Test the Server

The server will be available at:

- Health check: `http://localhost:3000/api/health`
- Email endpoint: `http://localhost:3000/api/send-email`

### 6. Update Flutter App

In your Flutter app, update the email service configuration:

```dart
// In lib/services/email_notification_service.dart
static const String _customServerUrl = 'http://your-server-ip:3000/api/send-email';
static const bool _useCustomServer = true;
static const bool _useCorsProxy = false;
```

## Deployment Options

### Option 1: Railway (Recommended - Easiest)

1. Sign up at [railway.app](https://railway.app)
2. Create new project → Deploy from GitHub
3. Add environment variables:
   - `EMAIL_USER=your-email@gmail.com`
   - `EMAIL_PASSWORD=your-app-password`
4. Set build command: `npm install`
5. Set start command: `node database-monitor.js`
6. Deploy! Service runs 24/7 automatically

**See `DEPLOYMENT_GUIDE.md` for detailed instructions**

### Option 2: Render (Free Tier Available)

1. Sign up at [render.com](https://render.com)
2. Create new Web Service
3. Connect GitHub repository
4. Add environment variables (same as Railway)
5. Set root directory: `server`
6. Deploy!

### Option 3: PM2 (Local or VPS)

```bash
# Install PM2 globally
npm install -g pm2

# Start the monitor
pm2 start ecosystem.config.js

# Auto-start on boot
pm2 save
pm2 startup

# View logs
pm2 logs smartpipe-monitor
```

### Option 4: Manual Local Development

- Run on your local machine
- Use your local IP address in the Flutter app
- Good for development and testing

## Security Notes

- Never commit your `.env` file to version control
- Use environment variables in production
- Consider implementing API key authentication
- Use HTTPS in production

## Troubleshooting

### Common Issues:

1. **Authentication Failed**:

   - Check your email and password
   - Ensure 2FA is enabled for Gmail
   - Use app password instead of regular password

2. **Port Already in Use**:

   - Change the PORT in `.env` file
   - Kill existing processes using the port

3. **CORS Issues**:

   - The server includes CORS middleware
   - Check if your Flutter app can reach the server

4. **Email Not Sending**:
   - Check server logs for errors
   - Verify email configuration
   - Test with a simple email first
