const express = require('express');
const nodemailer = require('nodemailer');
const cors = require('cors');
const emailTemplates = require('./email-templates');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Email transporter configuration
const transporter = nodemailer.createTransport({
  service: 'gmail', // or 'outlook', 'yahoo', etc.
  auth: {
    user: process.env.EMAIL_USER, // Your email address
    pass: process.env.EMAIL_PASSWORD, // Your email password or app password
  },
});

// Email sending endpoint
app.post('/api/send-email', async (req, res) => {
  try {
    const {
      to,
      subject,
      deviceName,
      message,
      flowRate,
      timestamp,
      systemName,
    } = req.body;

    // Validate required fields
    if (!to || !subject || !deviceName || !message) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: to, subject, deviceName, message',
      });
    }

    // Create HTML email template
    const htmlContent = `
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="UTF-8" />
          <title>${subject}</title>
        </head>
        <body style="font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #f8f9fa;">
          <div style="max-width: 600px; margin: 0 auto; background-color: white;">
            <!-- Header -->
            <div style="background: linear-gradient(135deg, #dc2626, #b91c1c); color: white; padding: 30px 20px; text-align: center;">
              <h1 style="margin: 0; font-size: 28px;">🚨 WATER LEAK ALERT</h1>
              <p style="margin: 10px 0 0 0; font-size: 16px;">${systemName || 'SmartPipe Water Management System'}</p>
            </div>

            <!-- Alert Message -->
            <div style="background-color: #fef2f2; border: 2px solid #fecaca; padding: 20px; margin: 20px; border-radius: 8px; text-align: center;">
              <h2 style="color: #dc2626; margin: 0 0 10px 0;">🚰 Leak Detected!</h2>
              <p style="color: #dc2626; font-weight: bold; font-size: 16px;">
                ${message}
              </p>
            </div>

            <!-- Details -->
            <div style="padding: 20px; margin: 20px; background-color: #f8fafc; border-radius: 8px;">
              <h3 style="color: #1f2937; margin-top: 0;">📊 Alert Details</h3>
              <table style="width: 100%; border-collapse: collapse;">
                <tr>
                  <td style="padding: 8px 0; font-weight: bold; color: #374151;">
                    🏷️ Device:
                  </td>
                  <td style="padding: 8px 0; color: #1f2937;">${deviceName}</td>
                </tr>
                <tr>
                  <td style="padding: 8px 0; font-weight: bold; color: #374151;">
                    💧 Flow Rate:
                  </td>
                  <td style="padding: 8px 0; color: #1f2937;">${flowRate || 'N/A'}</td>
                </tr>
                <tr>
                  <td style="padding: 8px 0; font-weight: bold; color: #374151;">
                    ⏰ Time:
                  </td>
                  <td style="padding: 8px 0; color: #1f2937;">${timestamp || new Date().toLocaleString()}</td>
                </tr>
              </table>
            </div>

            <!-- Action Required -->
            <div style="padding: 20px; margin: 20px; background-color: #fffbeb; border-radius: 8px; border-left: 4px solid #f59e0b;">
              <h3 style="color: #92400e; margin-top: 0;">⚠️ Action Required</h3>
              <p style="color: #78350f;">
                Please check the affected device immediately and take necessary action
                to prevent water damage.
              </p>
            </div>

            <!-- Footer -->
            <div style="background-color: #f3f4f6; padding: 20px; text-align: center; color: #6b7280; font-size: 14px;">
              <p style="margin: 0;">
                This is an automated alert from ${systemName || 'SmartPipe Water Management System'}
              </p>
              <p style="margin: 5px 0;">Alert sent at: ${timestamp || new Date().toLocaleString()}</p>
            </div>
          </div>
        </body>
      </html>
    `;

    // Send email
    const mailOptions = {
      from: process.env.EMAIL_USER,
      to: to,
      subject: subject,
      html: htmlContent,
    };

    const info = await transporter.sendMail(mailOptions);

    console.log('Email sent successfully:', info.messageId);
    res.json({
      success: true,
      messageId: info.messageId,
      message: 'Email sent successfully',
    });
  } catch (error) {
    console.error('Error sending email:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Generic email endpoint for any content from Flutter app
app.post('/api/send-generic-email', async (req, res) => {
  try {
    const {
      to,
      subject,
      content,
      contentType = 'text', // 'text' or 'html'
      attachments = [],
      priority = 'normal', // 'low', 'normal', 'high'
    } = req.body;

    // Validate required fields
    if (!to || !subject || !content) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: to, subject, content',
      });
    }

    // Create email options
    const mailOptions = {
      from: process.env.EMAIL_USER,
      to: to,
      subject: subject,
      priority: priority,
    };

    // Set content based on type
    if (contentType === 'html') {
      mailOptions.html = content;
    } else {
      mailOptions.text = content;
    }

    // Add attachments if provided
    if (attachments && attachments.length > 0) {
      mailOptions.attachments = attachments;
    }

    const info = await transporter.sendMail(mailOptions);

    console.log('Generic email sent successfully:', info.messageId);
    res.json({
      success: true,
      messageId: info.messageId,
      message: 'Email sent successfully',
    });
  } catch (error) {
    console.error('Error sending generic email:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Manual activities report email endpoint
app.post('/api/send-manual-activities-report', async (req, res) => {
  try {
    const {
      to,
      deviceId,
      activities,
      reportDate,
      summary,
    } = req.body;

    // Validate required fields
    if (!to || !deviceId || !activities) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: to, deviceId, activities',
      });
    }

    // Create HTML email template for manual activities
    const htmlContent = `
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="UTF-8" />
          <title>Manual Activities Report - ${deviceId}</title>
        </head>
        <body style="font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #f8f9fa;">
          <div style="max-width: 700px; margin: 0 auto; background-color: white;">
            <!-- Header -->
            <div style="background: linear-gradient(135deg, #2563eb, #1d4ed8); color: white; padding: 30px 20px; text-align: center;">
              <h1 style="margin: 0; font-size: 28px;">📋 Manual Activities Report</h1>
              <p style="margin: 10px 0 0 0; font-size: 16px;">Device: ${deviceId}</p>
              <p style="margin: 5px 0 0 0; font-size: 14px;">${reportDate || new Date().toLocaleDateString()}</p>
            </div>

            <!-- Summary Section -->
            ${summary ? `
            <div style="padding: 20px; margin: 20px; background-color: #f0f9ff; border-radius: 8px; border-left: 4px solid #0ea5e9;">
              <h3 style="color: #0c4a6e; margin-top: 0;">📊 Summary</h3>
              <p style="color: #0c4a6e; margin: 0;">${summary}</p>
            </div>
            ` : ''}

            <!-- Activities List -->
            <div style="padding: 20px; margin: 20px; background-color: #f8fafc; border-radius: 8px;">
              <h3 style="color: #1f2937; margin-top: 0;">🔧 Activities Performed</h3>
              <div style="max-height: 400px; overflow-y: auto;">
                ${activities.map((activity, index) => `
                  <div style="border: 1px solid #e5e7eb; border-radius: 6px; padding: 15px; margin-bottom: 10px; background-color: white;">
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                      <h4 style="margin: 0; color: #374151; font-size: 16px;">Activity ${index + 1}</h4>
                      <span style="background-color: #10b981; color: white; padding: 4px 8px; border-radius: 12px; font-size: 12px; font-weight: bold;">
                        ${activity.timestamp ? new Date(activity.timestamp).toLocaleString() : 'N/A'}
                      </span>
                    </div>
                    <p style="margin: 5px 0; color: #6b7280; font-size: 14px;">
                      <strong>Type:</strong> ${activity.type || 'N/A'}
                    </p>
                    <p style="margin: 5px 0; color: #6b7280; font-size: 14px;">
                      <strong>Description:</strong> ${activity.description || 'N/A'}
                    </p>
                    ${activity.operator ? `
                      <p style="margin: 5px 0; color: #6b7280; font-size: 14px;">
                        <strong>Operator:</strong> ${activity.operator}
                      </p>
                    ` : ''}
                    ${activity.duration ? `
                      <p style="margin: 5px 0; color: #6b7280; font-size: 14px;">
                        <strong>Duration:</strong> ${activity.duration}
                      </p>
                    ` : ''}
                  </div>
                `).join('')}
              </div>
            </div>

            <!-- Footer -->
            <div style="background-color: #f3f4f6; padding: 20px; text-align: center; color: #6b7280; font-size: 14px;">
              <p style="margin: 0;">
                This report was generated automatically from SmartPipe Water Management System
              </p>
              <p style="margin: 5px 0;">Report generated at: ${new Date().toLocaleString()}</p>
            </div>
          </div>
        </body>
      </html>
    `;

    // Send email
    const mailOptions = {
      from: process.env.EMAIL_USER,
      to: to,
      subject: `Manual Activities Report - ${deviceId} - ${reportDate || new Date().toLocaleDateString()}`,
      html: htmlContent,
    };

    const info = await transporter.sendMail(mailOptions);

    console.log('Manual activities report email sent successfully:', info.messageId);
    res.json({
      success: true,
      messageId: info.messageId,
      message: 'Manual activities report email sent successfully',
    });
  } catch (error) {
    console.error('Error sending manual activities report email:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Water consumption report email endpoint
app.post('/api/send-consumption-report', async (req, res) => {
  try {
    const {
      to,
      reportType,
      consumption,
      date,
      startDate,
      endDate,
      month,
      year,
      daysInMonth,
      deviceLabels,
      period,
      subject,
      attachments = [],
    } = req.body;

    // Validate required fields
    if (!to || !reportType || !consumption) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: to, reportType, consumption',
      });
    }

    // Select the appropriate email template based on report type
    let htmlContent;
    const templateData = {
      consumption: consumption,
      deviceLabels: deviceLabels || {},
    };

    switch (reportType) {
      case 'daily_consumption':
      case 'daily':
        templateData.date = date;
        htmlContent = emailTemplates.dailyConsumptionReport(templateData);
        break;
      case 'weekly_consumption':
      case 'weekly':
        templateData.startDate = startDate;
        templateData.endDate = endDate;
        htmlContent = emailTemplates.weeklyConsumptionReport(templateData);
        break;
      case 'monthly_consumption':
      case 'monthly':
        templateData.month = month;
        templateData.year = year;
        templateData.daysInMonth = daysInMonth;
        htmlContent = emailTemplates.monthlyConsumptionReport(templateData);
        break;
      case 'yearly_consumption':
      case 'yearly':
        templateData.year = year;
        htmlContent = emailTemplates.yearlyConsumptionReport(templateData);
        break;
      case 'summary':
      case 'comprehensive':
        templateData.period = period || 'All Time';
        htmlContent = emailTemplates.summaryReport(templateData);
        break;
      default:
        return res.status(400).json({
          success: false,
          error: 'Invalid reportType. Must be: daily, weekly, monthly, yearly, or summary',
        });
    }

    // Generate default subject if not provided
    const defaultSubject = subject || `Water Consumption Report - ${reportType.charAt(0).toUpperCase() + reportType.slice(1)}`;

    // Send email
    const mailOptions = {
      from: process.env.EMAIL_USER,
      to: Array.isArray(to) ? to.join(', ') : to,
      subject: defaultSubject,
      html: htmlContent,
    };

    // Add attachments if provided
    if (attachments && attachments.length > 0) {
      mailOptions.attachments = attachments.map(att => {
        if (att.content && att.filename) {
          return {
            filename: att.filename,
            content: Buffer.from(att.content, att.encoding || 'base64'),
          };
        }
        return att;
      });
    }

    const info = await transporter.sendMail(mailOptions);

    console.log('Consumption report email sent successfully:', info.messageId);
    res.json({
      success: true,
      messageId: info.messageId,
      message: 'Consumption report email sent successfully',
      reportType: reportType,
    });
  } catch (error) {
    console.error('Error sending consumption report email:', error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({
    success: true,
    message: 'Email server is running',
    timestamp: new Date().toISOString(),
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`Email server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/api/health`);
  console.log(`Water leak alerts: http://localhost:${PORT}/api/send-email`);
  console.log(`Generic emails: http://localhost:${PORT}/api/send-generic-email`);
  console.log(`Manual activities reports: http://localhost:${PORT}/api/send-manual-activities-report`);
  console.log(`Consumption reports: http://localhost:${PORT}/api/send-consumption-report`);
});

module.exports = app; 