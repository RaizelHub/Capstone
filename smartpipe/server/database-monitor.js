const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const cors = require('cors');
const sharedEmailTemplates = require('./email-templates');
require('dotenv').config();

function decodeServiceAccount(jsonString) {
  if (!jsonString) return null;

  try {
    const decoded = Buffer.from(jsonString, 'base64').toString('utf8');
    const parsedDecoded = JSON.parse(decoded);
    if (parsedDecoded && typeof parsedDecoded === 'object') {
      return parsedDecoded;
    }
  } catch (_) {
    // Not base64 or not valid JSON; ignore and try raw string.
  }

  try {
    return JSON.parse(jsonString);
  } catch (error) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT must be valid JSON or base64-encoded JSON.',
    );
  }
}

function resolveFirebaseCredential() {
  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (inlineJson) {
    const serviceAccount = decodeServiceAccount(inlineJson);
    return admin.credential.cert(serviceAccount);
  }

  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return admin.credential.applicationDefault();
  }

  throw new Error(
    'Missing Firebase credentials. Set FIREBASE_SERVICE_ACCOUNT or GOOGLE_APPLICATION_CREDENTIALS.',
  );
}

const databaseURL = process.env.FIREBASE_DATABASE_URL;
if (!databaseURL) {
  throw new Error('Missing FIREBASE_DATABASE_URL environment variable.');
}

admin.initializeApp({
  credential: resolveFirebaseCredential(),
  databaseURL,
});

const db = admin.database();

// Cache for recipients and leak alert listeners
let cachedRecipients = [];
const leakAlertListeners = {};

// Email transporter configuration
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASSWORD,
  },
});

// Email templates
const emailTemplates = {
  waterLeakAlert: (data) => `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Water Leak Alert</title>
    </head>
    <body style="font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #f8f9fa;">
      <div style="max-width: 600px; margin: 0 auto; background-color: white;">
        <div style="background: linear-gradient(135deg, #dc2626, #b91c1c); color: white; padding: 30px 20px; text-align: center;">
          <h1 style="margin: 0; font-size: 28px;">🚨 WATER LEAK ALERT</h1>
          <p style="margin: 10px 0 0 0; font-size: 16px;">${data.systemName || 'SmartPipe Water Management System'}</p>
        </div>
        
        <div style="background-color: #fef2f2; border: 2px solid #fecaca; padding: 20px; margin: 20px; border-radius: 8px; text-align: center;">
          <h2 style="color: #dc2626; margin: 0 0 10px 0;">🚰 Leak Detected!</h2>
          <p style="color: #dc2626; font-weight: bold; font-size: 16px;">${data.message}</p>
        </div>
        
        <div style="padding: 20px; margin: 20px; background-color: #f8fafc; border-radius: 8px;">
          <h3 style="color: #1f2937; margin-top: 0;">📊 Alert Details</h3>
          <table style="width: 100%; border-collapse: collapse;">
            <tr>
              <td style="padding: 8px 0; font-weight: bold; color: #374151;">🏷️ Device:</td>
              <td style="padding: 8px 0; color: #1f2937;">${data.deviceName}</td>
            </tr>
            <tr>
              <td style="padding: 8px 0; font-weight: bold; color: #374151;">💧 Flow Rate:</td>
              <td style="padding: 8px 0; color: #1f2937;">${data.flowRate || 'N/A'}</td>
            </tr>
            <tr>
              <td style="padding: 8px 0; font-weight: bold; color: #374151;">⏰ Time:</td>
              <td style="padding: 8px 0; color: #1f2937;">${data.timestamp || new Date().toLocaleString()}</td>
            </tr>
          </table>
        </div>
        
        <div style="background-color: #f3f4f6; padding: 20px; text-align: center; color: #6b7280; font-size: 14px;">
          <p style="margin: 0;">This is an automated alert from ${data.systemName || 'SmartPipe Water Management System'}</p>
          <p style="margin: 5px 0;">Alert sent at: ${new Date().toLocaleString()}</p>
        </div>
      </div>
    </body>
    </html>
  `,
  
  manualActivitiesReport: (data) => `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Manual Activities Report</title>
    </head>
    <body style="font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #f8f9fa;">
      <div style="max-width: 700px; margin: 0 auto; background-color: white;">
        <div style="background: linear-gradient(135deg, #2563eb, #1d4ed8); color: white; padding: 30px 20px; text-align: center;">
          <h1 style="margin: 0; font-size: 28px;">📋 Manual Activities Report</h1>
          <p style="margin: 10px 0 0 0; font-size: 16px;">Device: ${data.deviceId}</p>
          <p style="margin: 5px 0 0 0; font-size: 14px;">${data.reportDate || new Date().toLocaleDateString()}</p>
        </div>
        
        ${data.summary ? `
        <div style="padding: 20px; margin: 20px; background-color: #f0f9ff; border-radius: 8px; border-left: 4px solid #0ea5e9;">
          <h3 style="color: #0c4a6e; margin-top: 0;">📊 Summary</h3>
          <p style="color: #0c4a6e; margin: 0;">${data.summary}</p>
        </div>
        ` : ''}
        
        <div style="padding: 20px; margin: 20px; background-color: #f8fafc; border-radius: 8px;">
          <h3 style="color: #1f2937; margin-top: 0;">🔧 Activities Performed</h3>
          <div style="max-height: 400px; overflow-y: auto;">
            ${data.activities.map((activity, index) => `
              <div style="border: 1px solid #e5e7eb; border-radius: 6px; padding: 15px; margin-bottom: 10px; background-color: white;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                  <h4 style="margin: 0; color: #374151; font-size: 16px;">Activity ${index + 1}</h4>
                  <span style="background-color: #10b981; color: white; padding: 4px 8px; border-radius: 12px; font-size: 12px; font-weight: bold;">
                    ${activity.timestamp ? new Date(activity.timestamp).toLocaleString() : 'N/A'}
                  </span>
                </div>
                <p style="margin: 5px 0; color: #6b7280; font-size: 14px;"><strong>Type:</strong> ${activity.type || 'N/A'}</p>
                <p style="margin: 5px 0; color: #6b7280; font-size: 14px;"><strong>Description:</strong> ${activity.description || 'N/A'}</p>
                ${activity.operator ? `<p style="margin: 5px 0; color: #6b7280; font-size: 14px;"><strong>Operator:</strong> ${activity.operator}</p>` : ''}
                ${activity.duration ? `<p style="margin: 5px 0; color: #6b7280; font-size: 14px;"><strong>Duration:</strong> ${activity.duration}</p>` : ''}
              </div>
            `).join('')}
          </div>
        </div>
        
        <div style="background-color: #f3f4f6; padding: 20px; text-align: center; color: #6b7280; font-size: 14px;">
          <p style="margin: 0;">This report was generated automatically from SmartPipe Water Management System</p>
          <p style="margin: 5px 0;">Report generated at: ${new Date().toLocaleString()}</p>
        </div>
      </div>
    </body>
    </html>
  `,

  // Daily Consumption Report Template
  dailyConsumptionReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    const reportDate = data.date ? new Date(data.date).toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }) : new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Daily Water Consumption Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #0ea5e9, #0284c7); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">💧</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Daily Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">${reportDate}</p>
          </div>

          <!-- Total Consumption Highlight -->
          <div style="background: linear-gradient(135deg, #ecfeff, #cffafe); padding: 30px; margin: 30px; border-radius: 12px; text-align: center; border: 2px solid #06b6d4;">
            <div style="font-size: 14px; color: #0891b2; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Total Consumption</div>
            <div style="font-size: 48px; font-weight: 700; color: #0e7490; margin: 10px 0;">${totalConsumption.toFixed(1)}</div>
            <div style="font-size: 18px; color: #0891b2; font-weight: 500;">Liters</div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Device Breakdown</h2>
            ${devices.length > 0 ? devices.map(deviceId => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              return `
              <div style="background-color: #f8fafc; border-radius: 10px; padding: 20px; margin-bottom: 15px; border-left: 4px solid #0ea5e9;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                  <div>
                    <div style="font-size: 16px; font-weight: 600; color: #1e293b; margin-bottom: 4px;">${deviceName}</div>
                    <div style="font-size: 12px; color: #64748b;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 28px; font-weight: 700; color: #0ea5e9;">${liters.toFixed(1)}</div>
                    <div style="font-size: 12px; color: #64748b;">Liters</div>
                  </div>
                </div>
                <div style="background-color: #e0f2fe; border-radius: 8px; height: 8px; overflow: hidden;">
                  <div style="background: linear-gradient(90deg, #0ea5e9, #0284c7); height: 100%; width: ${percentage}%; border-radius: 8px; transition: width 0.3s ease;"></div>
                </div>
                <div style="font-size: 12px; color: #64748b; margin-top: 6px;">${percentage}% of total consumption</div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 20px;">No consumption data available for this period.</p>'}
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #0ea5e9; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Weekly Consumption Report Template
  weeklyConsumptionReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    const avgDaily = totalConsumption / 7;
    const startDate = data.startDate ? new Date(data.startDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '';
    const endDate = data.endDate ? new Date(data.endDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '';
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Weekly Water Consumption Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #8b5cf6, #7c3aed); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">📅</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Weekly Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">${startDate} - ${endDate}</p>
          </div>

          <!-- Key Metrics -->
          <div style="padding: 30px; display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
            <div style="background: linear-gradient(135deg, #faf5ff, #f3e8ff); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #a78bfa;">
              <div style="font-size: 14px; color: #7c3aed; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Total Weekly</div>
              <div style="font-size: 36px; font-weight: 700; color: #6d28d9; margin: 10px 0;">${totalConsumption.toFixed(1)}</div>
              <div style="font-size: 16px; color: #7c3aed; font-weight: 500;">Liters</div>
            </div>
            <div style="background: linear-gradient(135deg, #fef3c7, #fde68a); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #fbbf24;">
              <div style="font-size: 14px; color: #d97706; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Daily Average</div>
              <div style="font-size: 36px; font-weight: 700; color: #b45309; margin: 10px 0;">${avgDaily.toFixed(1)}</div>
              <div style="font-size: 16px; color: #d97706; font-weight: 500;">Liters/Day</div>
            </div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Device Performance</h2>
            ${devices.length > 0 ? devices.map(deviceId => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const dailyAvg = liters / 7;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              return `
              <div style="background-color: #f8fafc; border-radius: 10px; padding: 20px; margin-bottom: 15px; border-left: 4px solid #8b5cf6;">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px;">
                  <div style="flex: 1;">
                    <div style="font-size: 16px; font-weight: 600; color: #1e293b; margin-bottom: 4px;">${deviceName}</div>
                    <div style="font-size: 12px; color: #64748b;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 24px; font-weight: 700; color: #8b5cf6;">${liters.toFixed(1)}</div>
                    <div style="font-size: 11px; color: #64748b;">Liters (Week)</div>
                    <div style="font-size: 14px; color: #7c3aed; margin-top: 4px; font-weight: 600;">${dailyAvg.toFixed(1)} L/day</div>
                  </div>
                </div>
                <div style="background-color: #f3e8ff; border-radius: 8px; height: 8px; overflow: hidden;">
                  <div style="background: linear-gradient(90deg, #8b5cf6, #7c3aed); height: 100%; width: ${percentage}%; border-radius: 8px;"></div>
                </div>
                <div style="font-size: 12px; color: #64748b; margin-top: 6px;">${percentage}% of weekly total</div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 20px;">No consumption data available for this period.</p>'}
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #8b5cf6; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Monthly Consumption Report Template
  monthlyConsumptionReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    const daysInMonth = data.daysInMonth || 30;
    const avgDaily = totalConsumption / daysInMonth;
    const monthName = data.month ? new Date(2024, data.month - 1, 1).toLocaleDateString('en-US', { month: 'long' }) : new Date().toLocaleDateString('en-US', { month: 'long' });
    const year = data.year || new Date().getFullYear();
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Monthly Water Consumption Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #10b981, #059669); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">📊</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Monthly Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">${monthName} ${year}</p>
          </div>

          <!-- Key Metrics -->
          <div style="padding: 30px; display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 15px;">
            <div style="background: linear-gradient(135deg, #d1fae5, #a7f3d0); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #34d399;">
              <div style="font-size: 12px; color: #059669; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Total Monthly</div>
              <div style="font-size: 32px; font-weight: 700; color: #047857; margin: 10px 0;">${totalConsumption.toFixed(1)}</div>
              <div style="font-size: 14px; color: #059669; font-weight: 500;">Liters</div>
            </div>
            <div style="background: linear-gradient(135deg, #dbeafe, #bfdbfe); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #60a5fa;">
              <div style="font-size: 12px; color: #2563eb; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Daily Average</div>
              <div style="font-size: 32px; font-weight: 700; color: #1e40af; margin: 10px 0;">${avgDaily.toFixed(1)}</div>
              <div style="font-size: 14px; color: #2563eb; font-weight: 500;">Liters/Day</div>
            </div>
            <div style="background: linear-gradient(135deg, #fef3c7, #fde68a); padding: 25px; border-radius: 12px; text-align: center; border: 2px solid #fbbf24;">
              <div style="font-size: 12px; color: #d97706; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Est. Monthly</div>
              <div style="font-size: 32px; font-weight: 700; color: #b45309; margin: 10px 0;">${(avgDaily * 30).toFixed(0)}</div>
              <div style="font-size: 14px; color: #d97706; font-weight: 500;">Liters</div>
            </div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Device Analysis</h2>
            ${devices.length > 0 ? devices.map(deviceId => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const dailyAvg = liters / daysInMonth;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              return `
              <div style="background-color: #f8fafc; border-radius: 10px; padding: 20px; margin-bottom: 15px; border-left: 4px solid #10b981;">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px;">
                  <div style="flex: 1;">
                    <div style="font-size: 16px; font-weight: 600; color: #1e293b; margin-bottom: 4px;">${deviceName}</div>
                    <div style="font-size: 12px; color: #64748b;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 24px; font-weight: 700; color: #10b981;">${liters.toFixed(1)}</div>
                    <div style="font-size: 11px; color: #64748b;">Liters (Month)</div>
                    <div style="font-size: 14px; color: #059669; margin-top: 4px; font-weight: 600;">${dailyAvg.toFixed(1)} L/day</div>
                  </div>
                </div>
                <div style="background-color: #d1fae5; border-radius: 8px; height: 10px; overflow: hidden;">
                  <div style="background: linear-gradient(90deg, #10b981, #059669); height: 100%; width: ${percentage}%; border-radius: 8px;"></div>
                </div>
                <div style="font-size: 12px; color: #64748b; margin-top: 6px;">${percentage}% of monthly total</div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 20px;">No consumption data available for this period.</p>'}
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #10b981; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Yearly Consumption Report Template
  yearlyConsumptionReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    const avgDaily = totalConsumption / 365;
    const avgMonthly = totalConsumption / 12;
    const year = data.year || new Date().getFullYear();
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Yearly Water Consumption Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #f59e0b, #d97706); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">📈</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Yearly Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">Annual Report ${year}</p>
          </div>

          <!-- Key Metrics -->
          <div style="padding: 30px; display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
            <div style="background: linear-gradient(135deg, #fef3c7, #fde68a); padding: 30px; border-radius: 12px; text-align: center; border: 2px solid #fbbf24;">
              <div style="font-size: 14px; color: #d97706; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Total Annual</div>
              <div style="font-size: 42px; font-weight: 700; color: #b45309; margin: 10px 0;">${totalConsumption.toFixed(1)}</div>
              <div style="font-size: 16px; color: #d97706; font-weight: 500;">Liters</div>
            </div>
            <div style="background: linear-gradient(135deg, #dbeafe, #bfdbfe); padding: 30px; border-radius: 12px; text-align: center; border: 2px solid #60a5fa;">
              <div style="font-size: 14px; color: #2563eb; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Monthly Average</div>
              <div style="font-size: 42px; font-weight: 700; color: #1e40af; margin: 10px 0;">${avgMonthly.toFixed(1)}</div>
              <div style="font-size: 16px; color: #2563eb; font-weight: 500;">Liters/Month</div>
            </div>
          </div>

          <div style="padding: 0 30px 20px 30px; display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
            <div style="background-color: #f8fafc; padding: 20px; border-radius: 10px; text-align: center; border: 1px solid #e2e8f0;">
              <div style="font-size: 12px; color: #64748b; font-weight: 600; text-transform: uppercase; margin-bottom: 6px;">Daily Average</div>
              <div style="font-size: 28px; font-weight: 700; color: #1e293b;">${avgDaily.toFixed(1)}</div>
              <div style="font-size: 14px; color: #64748b;">Liters/Day</div>
            </div>
            <div style="background-color: #f8fafc; padding: 20px; border-radius: 10px; text-align: center; border: 1px solid #e2e8f0;">
              <div style="font-size: 12px; color: #64748b; font-weight: 600; text-transform: uppercase; margin-bottom: 6px;">Total Devices</div>
              <div style="font-size: 28px; font-weight: 700; color: #1e293b;">${devices.length}</div>
              <div style="font-size: 14px; color: #64748b;">Active Devices</div>
            </div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Annual Device Performance</h2>
            ${devices.length > 0 ? devices.map(deviceId => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const monthlyAvg = liters / 12;
              const dailyAvg = liters / 365;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              return `
              <div style="background-color: #f8fafc; border-radius: 10px; padding: 20px; margin-bottom: 15px; border-left: 4px solid #f59e0b;">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px;">
                  <div style="flex: 1;">
                    <div style="font-size: 16px; font-weight: 600; color: #1e293b; margin-bottom: 4px;">${deviceName}</div>
                    <div style="font-size: 12px; color: #64748b;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 24px; font-weight: 700; color: #f59e0b;">${liters.toFixed(1)}</div>
                    <div style="font-size: 11px; color: #64748b;">Liters (Year)</div>
                    <div style="font-size: 13px; color: #d97706; margin-top: 4px; font-weight: 600;">${monthlyAvg.toFixed(1)} L/month</div>
                    <div style="font-size: 12px; color: #92400e; margin-top: 2px;">${dailyAvg.toFixed(1)} L/day</div>
                  </div>
                </div>
                <div style="background-color: #fef3c7; border-radius: 8px; height: 10px; overflow: hidden;">
                  <div style="background: linear-gradient(90deg, #f59e0b, #d97706); height: 100%; width: ${percentage}%; border-radius: 8px;"></div>
                </div>
                <div style="font-size: 12px; color: #64748b; margin-top: 6px;">${percentage}% of annual total</div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 20px;">No consumption data available for this period.</p>'}
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #f59e0b; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Summary Report Template (Comprehensive)
  summaryReport: (data) => {
    const consumptionData = data.consumption || {};
    const devices = Object.keys(consumptionData);
    const totalConsumption = Object.values(consumptionData).reduce((sum, val) => sum + (parseFloat(val) || 0), 0);
    
    return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Water Consumption Summary Report</title>
      </head>
      <body style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f0f4f8;">
        <div style="max-width: 700px; margin: 0 auto; background-color: white; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #6366f1, #4f46e5); color: white; padding: 40px 30px; text-align: center;">
            <div style="font-size: 48px; margin-bottom: 10px;">📑</div>
            <h1 style="margin: 0; font-size: 32px; font-weight: 700;">Comprehensive Water Consumption</h1>
            <p style="margin: 10px 0 0 0; font-size: 18px; opacity: 0.95;">Summary Report</p>
          </div>

          <!-- Total Consumption Highlight -->
          <div style="background: linear-gradient(135deg, #eef2ff, #e0e7ff); padding: 35px; margin: 30px; border-radius: 12px; text-align: center; border: 3px solid #6366f1;">
            <div style="font-size: 16px; color: #4f46e5; font-weight: 600; text-transform: uppercase; letter-spacing: 1.5px; margin-bottom: 10px;">Total Consumption</div>
            <div style="font-size: 56px; font-weight: 700; color: #4338ca; margin: 15px 0;">${totalConsumption.toFixed(1)}</div>
            <div style="font-size: 20px; color: #4f46e5; font-weight: 500;">Liters</div>
            <div style="margin-top: 15px; padding-top: 15px; border-top: 2px solid #c7d2fe;">
              <div style="font-size: 14px; color: #6366f1;">Across ${devices.length} device${devices.length !== 1 ? 's' : ''}</div>
            </div>
          </div>

          <!-- Device Breakdown -->
          <div style="padding: 0 30px 30px 30px;">
            <h2 style="color: #1e293b; font-size: 24px; margin: 0 0 20px 0; padding-bottom: 10px; border-bottom: 2px solid #e2e8f0;">📊 Complete Device Analysis</h2>
            ${devices.length > 0 ? devices.map((deviceId, index) => {
              const liters = parseFloat(consumptionData[deviceId]) || 0;
              const percentage = totalConsumption > 0 ? ((liters / totalConsumption) * 100).toFixed(1) : 0;
              const deviceName = data.deviceLabels && data.deviceLabels[deviceId] ? data.deviceLabels[deviceId] : deviceId;
              const colors = ['#6366f1', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981', '#06b6d4'];
              const color = colors[index % colors.length];
              return `
              <div style="background-color: #f8fafc; border-radius: 12px; padding: 25px; margin-bottom: 18px; border-left: 5px solid ${color}; box-shadow: 0 2px 4px rgba(0,0,0,0.05);">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
                  <div style="flex: 1;">
                    <div style="display: flex; align-items: center; margin-bottom: 6px;">
                      <div style="width: 12px; height: 12px; background-color: ${color}; border-radius: 50%; margin-right: 10px;"></div>
                      <div style="font-size: 18px; font-weight: 600; color: #1e293b;">${deviceName}</div>
                    </div>
                    <div style="font-size: 13px; color: #64748b; margin-left: 22px;">${deviceId}</div>
                  </div>
                  <div style="text-align: right;">
                    <div style="font-size: 32px; font-weight: 700; color: ${color};">${liters.toFixed(1)}</div>
                    <div style="font-size: 13px; color: #64748b; margin-top: 4px;">Liters</div>
                  </div>
                </div>
                <div style="background-color: #e0e7ff; border-radius: 10px; height: 12px; overflow: hidden; margin-bottom: 8px;">
                  <div style="background: linear-gradient(90deg, ${color}, ${color}dd); height: 100%; width: ${percentage}%; border-radius: 10px; transition: width 0.3s ease;"></div>
                </div>
                <div style="display: flex; justify-content: space-between; align-items: center;">
                  <div style="font-size: 13px; color: #64748b; font-weight: 500;">${percentage}% of total consumption</div>
                  <div style="font-size: 13px; color: ${color}; font-weight: 600;">Rank #${index + 1}</div>
                </div>
              </div>
              `;
            }).join('') : '<p style="color: #64748b; text-align: center; padding: 30px; background-color: #f8fafc; border-radius: 10px;">No consumption data available.</p>'}
          </div>

          <!-- Additional Info -->
          <div style="background: linear-gradient(135deg, #f8fafc, #f1f5f9); padding: 25px 30px; margin: 0 30px 30px 30px; border-radius: 10px; border: 1px solid #e2e8f0;">
            <div style="font-size: 14px; color: #475569; line-height: 1.8;">
              <p style="margin: 0 0 10px 0;"><strong>📌 Report Period:</strong> ${data.period || 'All Time'}</p>
              <p style="margin: 0 0 10px 0;"><strong>📅 Generated:</strong> ${new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}</p>
              <p style="margin: 0;"><strong>⏰ Time:</strong> ${new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}</p>
            </div>
          </div>

          <!-- Footer -->
          <div style="background-color: #f1f5f9; padding: 25px 30px; text-align: center; border-top: 1px solid #e2e8f0;">
            <p style="margin: 0; color: #64748b; font-size: 14px;">This comprehensive report was generated automatically by</p>
            <p style="margin: 5px 0 0 0; color: #6366f1; font-weight: 600; font-size: 16px;">SmartPipe Water Management System</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">For detailed analysis, please refer to the attached PDF document.</p>
            <p style="margin: 10px 0 0 0; color: #94a3b8; font-size: 12px;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
    `;
  },

  // Generic Report Email (fallback)
  reportEmail: (data) => `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <title>SmartPipe Report</title>
      </head>
      <body style="font-family: Arial, sans-serif; margin: 0; padding: 0; background-color: #f8f9fa;">
        <div style="max-width: 600px; margin: 0 auto; background-color: white;">
          <div style="background: linear-gradient(135deg, #2563eb, #1d4ed8); color: white; padding: 30px 20px; text-align: center;">
            <h1 style="margin: 0; font-size: 26px;">📄 SmartPipe Report</h1>
            <p style="margin: 10px 0 0 0; font-size: 16px;">${
              data.reportPeriod || 'Comprehensive Report'
            }</p>
          </div>

          <div style="padding: 24px;">
            <h2 style="color: #1f2937; margin-top: 0;">Report Summary</h2>
            <p style="color: #374151; font-size: 15px;">
              ${data.message ||
                'Please find the attached SmartPipe report for your review.'}
            </p>
            <p style="color: #6b7280; font-size: 14px;">
              The detailed report is attached as a PDF document.
            </p>
          </div>

          <div style="background-color: #f3f4f6; padding: 20px; text-align: center; color: #6b7280; font-size: 14px;">
            <p style="margin: 0;">This report was generated automatically by the SmartPipe Water Management System.</p>
            <p style="margin: 5px 0;">Generated at: ${new Date().toLocaleString()}</p>
          </div>
        </div>
      </body>
    </html>
  `,

  // Merge with shared consumption report templates
  ...sharedEmailTemplates
};

// Function to send email
async function sendEmail(to, subject, htmlContent, attachments = []) {
  try {
    const mailOptions = {
      from: process.env.EMAIL_USER,
      to: to,
      subject: subject,
      html: htmlContent,
    };

    if (attachments && attachments.length > 0) {
      mailOptions.attachments = attachments;
    }

    const info = await transporter.sendMail(mailOptions);
    console.log('✅ Email sent successfully:', info.messageId);
    return { success: true, messageId: info.messageId };
  } catch (error) {
    console.error('❌ Error sending email:', error);
    return { success: false, error: error.message };
  }
}

function monitorReportEmails() {
  console.log('🔍 Monitoring report email notifications...');

  db.ref('notifications/reports')
    .orderByChild('status')
    .equalTo('pending')
    .on('child_added', async (snapshot) => {
      const reportData = snapshot.val();
      const reportId = snapshot.key;

      if (!reportData) {
        return;
      }

      const recipients = Array.isArray(reportData.recipients)
        ? reportData.recipients.filter(
            (email) => typeof email === 'string' && email.trim().length > 0,
          )
        : [];

      if (!recipients.length) {
        console.warn(
          `⚠️ Report notification ${reportId} has no recipients. Marking as failed.`,
        );
        await snapshot.ref.update({
          status: 'failed',
          processedAt: admin.database.ServerValue.TIMESTAMP,
          error: 'No recipients were provided.',
        });
        return;
      }

      const attachmentBase64 =
        reportData.attachment || reportData.attachmentBase64;
      const fileName =
        reportData.fileName || `smartpipe-report-${Date.now()}.pdf`;

      const attachments =
        attachmentBase64
          ? [
              {
                filename: fileName,
                content: Buffer.from(attachmentBase64, 'base64'),
              },
            ]
          : [];

      // Select the appropriate email template based on report type
      let htmlContent;
      const reportType = reportData.type || reportData.reportType || 'generic';
      const reportPeriod = reportData.reportPeriod || 'Comprehensive Report';

      switch (reportType) {
        case 'daily_consumption':
        case 'daily':
          htmlContent = emailTemplates.dailyConsumptionReport({
            consumption: reportData.consumption || reportData.totalConsumption || {},
            date: reportData.date,
            deviceLabels: reportData.deviceLabels || {},
          });
          break;
        case 'weekly_consumption':
        case 'weekly':
          htmlContent = emailTemplates.weeklyConsumptionReport({
            consumption: reportData.consumption || reportData.totalConsumption || {},
            startDate: reportData.startDate,
            endDate: reportData.endDate,
            deviceLabels: reportData.deviceLabels || {},
          });
          break;
        case 'monthly_consumption':
        case 'monthly':
          htmlContent = emailTemplates.monthlyConsumptionReport({
            consumption: reportData.consumption || reportData.totalConsumption || {},
            month: reportData.month,
            year: reportData.year,
            daysInMonth: reportData.daysInMonth,
            deviceLabels: reportData.deviceLabels || {},
          });
          break;
        case 'yearly_consumption':
        case 'yearly':
          htmlContent = emailTemplates.yearlyConsumptionReport({
            consumption: reportData.consumption || reportData.totalConsumption || {},
            year: reportData.year,
            deviceLabels: reportData.deviceLabels || {},
          });
          break;
        case 'summary':
        case 'comprehensive':
          htmlContent = emailTemplates.summaryReport({
            consumption: reportData.consumption || reportData.totalConsumption || {},
            period: reportPeriod,
            deviceLabels: reportData.deviceLabels || {},
          });
          break;
        case 'comprehensive_report':
          htmlContent = emailTemplates.comprehensiveReport({
            deviceCount: reportData.deviceCount || 0,
            totalLeaks: reportData.totalLeaks || 0,
            totalManual: reportData.totalManual || 0,
            period: reportPeriod,
            message: reportData.message,
            consumption: reportData.consumption || reportData.totalConsumption || {},
            deviceLabels: reportData.deviceLabels || {},
            generatedAt: reportData.generatedAt || new Date().toLocaleString(),
          });
          break;
        default:
          htmlContent = emailTemplates.reportEmail({
            reportPeriod: reportPeriod,
            message:
              reportData.message ||
              'Please find the attached SmartPipe report for your review.',
          });
      }

      let successCount = 0;

      for (const to of recipients) {
        const result = await sendEmail(
          to,
          reportData.subject || 'SmartPipe Report',
          htmlContent,
          attachments,
        );

        if (result.success) {
          successCount++;
        }
      }

      await snapshot.ref.update({
        status: successCount > 0 ? 'sent' : 'failed',
        sentAt: admin.database.ServerValue.TIMESTAMP,
        recipientsCount: successCount,
        lastResult:
          successCount > 0
            ? `Emails sent to ${successCount} recipient(s).`
            : 'All email attempts failed.',
      });

      console.log(
        successCount > 0
          ? `📄 Report notification ${reportId} sent to ${successCount} recipient(s).`
          : `⚠️ Report notification ${reportId} failed to send.`,
      );
    });
}

// Function to mark notification as sent
async function markNotificationAsSent(notificationId) {
  try {
    await db.ref(`notifications/${notificationId}`).update({
      status: 'sent',
      sentAt: admin.database.ServerValue.TIMESTAMP
    });
    console.log('✅ Notification marked as sent:', notificationId);
  } catch (error) {
    console.error('❌ Error marking notification as sent:', error);
  }
}

function startRecipientsWatcher() {
  console.log('🔍 Watching email recipients list...');
  db.ref('email_settings/recipients').on('value', (snapshot) => {
    const recipients = [];
    const val = snapshot.val();
    if (Array.isArray(val)) {
      val.forEach((item) => {
        if (typeof item === 'string' && item.trim().length > 0) {
          recipients.push(item.trim());
        }
      });
    } else if (val && typeof val === 'object') {
      Object.values(val).forEach((item) => {
        if (typeof item === 'string' && item.trim().length > 0) {
          recipients.push(item.trim());
        }
      });
    }
    cachedRecipients = [...new Set(recipients)];
    console.log(`✅ Recipients updated (${cachedRecipients.length})`);
  }, (err) => {
    console.error('❌ Failed to watch recipients list:', err);
  });
}

function attachLeakAlertListener(deviceId) {
  if (!deviceId || leakAlertListeners[deviceId]) {
    return;
  }

  const ref = db.ref(`readings/${deviceId}/leak_alerts`);
  console.log(`🔔 Attaching leak alert listener for device ${deviceId}`);

  leakAlertListeners[deviceId] = ref.limitToLast(50).on('child_added', async (snapshot) => {
    const alertData = snapshot.val();
    const alertId = snapshot.key;

    if (!alertData) {
      return;
    }

    if (alertData.status && alertData.status.toLowerCase() === 'sent') {
      console.log(`ℹ️ Leak alert ${deviceId}/${alertId} already sent. Skipping.`);
      return;
    }

    try {
      await handleLeakAlert(deviceId, alertId, alertData);
    } catch (error) {
      console.error(`❌ Failed to process leak alert ${deviceId}/${alertId}:`, error);
    }
  }, (error) => {
    console.error(`❌ Error listening to leak alerts for ${deviceId}:`, error);
  });
}

async function handleLeakAlert(deviceId, alertId, alertData) {
  const recipientsFromAlert = Array.isArray(alertData.recipients)
    ? alertData.recipients.filter((email) => typeof email === 'string' && email.trim().length > 0)
    : [];
  const recipients = recipientsFromAlert.length > 0 ? recipientsFromAlert : cachedRecipients;

  if (!recipients.length) {
    console.warn(`⚠️ No recipients configured for leak alert ${deviceId}/${alertId}.`);
    await db.ref(`readings/${deviceId}/leak_alerts/${alertId}`).update({
      status: 'pending_no_recipient',
      lastAttemptAt: admin.database.ServerValue.TIMESTAMP,
    });
    return;
  }

  const deviceName = alertData.deviceName || alertData.deviceLabel || deviceId;
  const flowRaw = alertData.flowRate ?? alertData.flow ?? alertData.flow_rate;
  const flowRate = typeof flowRaw === 'number'
    ? `${flowRaw.toFixed(2)} L/min`
    : (flowRaw ? `${flowRaw} L/min` : 'N/A');

  const timestamp = formatAlertTimestamp(alertData.timestamp ?? alertId);

  const message =
    alertData.message ||
    alertData.reason ||
    alertData.status ||
    'Leak detected by SmartPipe monitoring service.';

  const templateData = {
    deviceId,
    deviceName,
    flowRate,
    timestamp,
    message,
    systemName: alertData.systemName || 'SmartPipe Water Management System',
  };

  console.log(`📨 Sending leak alert emails for ${deviceId}/${alertId} to ${recipients.length} recipient(s).`);

  const htmlContent = emailTemplates.waterLeakAlert(templateData);

  for (const to of recipients) {
    try {
      await sendEmail(
        to,
        alertData.subject || `Water Leak Alert - ${deviceName}`,
        htmlContent,
      );
    } catch (error) {
      console.error(`❌ Failed to send leak alert email to ${to}:`, error);
    }
  }

  await db.ref(`readings/${deviceId}/leak_alerts/${alertId}`).update({
    status: 'sent',
    sentAt: admin.database.ServerValue.TIMESTAMP,
    processedBy: 'database-monitor',
  });

  console.log(`✅ Leak alert processed for ${deviceId}/${alertId}`);
}

function monitorRealtimeLeakAlerts() {
  console.log('🔍 Monitoring realtime leak alerts under readings/{deviceId}/leak_alerts');

  db.ref('readings').on('child_added', (snapshot) => {
    const deviceId = snapshot.key;
    attachLeakAlertListener(deviceId);
  }, (error) => {
    console.error('❌ Error monitoring readings root for leak alerts:', error);
  });

  db.ref('readings').once('value')
    .then((snapshot) => {
      snapshot.forEach((child) => {
        attachLeakAlertListener(child.key);
      });
    })
    .catch((error) => {
      console.error('❌ Error attaching initial leak alert listeners:', error);
    });
}

function formatAlertTimestamp(timestampField) {
  if (!timestampField) {
    return new Date().toLocaleString();
  }

  if (typeof timestampField === 'number') {
    if (timestampField > 1000000000000) {
      return new Date(timestampField).toLocaleString();
    }
    return new Date(timestampField * 1000).toLocaleString();
  }

  if (typeof timestampField === 'string') {
    const numeric = Number(timestampField);
    if (!Number.isNaN(numeric)) {
      return formatAlertTimestamp(numeric);
    }

    const parsed = Date.parse(timestampField);
    if (!Number.isNaN(parsed)) {
      return new Date(parsed).toLocaleString();
    }
  }

  return new Date().toLocaleString();
}

// Monitor water leak notifications
function monitorWaterLeakNotifications() {
  console.log('🔍 Monitoring water leak notifications...');
  
  db.ref('notifications/water_leaks').orderByChild('status').equalTo('pending').on('child_added', async (snapshot) => {
    const notification = snapshot.val();
    const notificationId = snapshot.key;
    
    console.log('🚨 New water leak notification detected:', notificationId);
    
    // Send email
    const htmlContent = emailTemplates.waterLeakAlert(notification);
    const result = await sendEmail(
      notification.to,
      notification.subject || 'Water Leak Alert',
      htmlContent
    );
    
    if (result.success) {
      await markNotificationAsSent(`water_leaks/${notificationId}`);
    }
  });
}

// Monitor manual activities notifications
function monitorManualActivitiesNotifications() {
  console.log('🔍 Monitoring manual activities notifications...');
  
  db.ref('notifications/manual_activities').orderByChild('status').equalTo('pending').on('child_added', async (snapshot) => {
    const notification = snapshot.val();
    const notificationId = snapshot.key;
    
    console.log('📋 New manual activities notification detected:', notificationId);
    
    // Send email
    const htmlContent = emailTemplates.manualActivitiesReport(notification);
    const result = await sendEmail(
      notification.to,
      notification.subject || `Manual Activities Report - ${notification.deviceId}`,
      htmlContent
    );
    
    if (result.success) {
      await markNotificationAsSent(`manual_activities/${notificationId}`);
    }
  });
}

// Monitor generic notifications
function monitorGenericNotifications() {
  console.log('🔍 Monitoring generic notifications...');
  
  db.ref('notifications/generic').orderByChild('status').equalTo('pending').on('child_added', async (snapshot) => {
    const notification = snapshot.val();
    const notificationId = snapshot.key;
    
    console.log('📧 New generic notification detected:', notificationId);
    
    // Send email
    const result = await sendEmail(
      notification.to,
      notification.subject,
      notification.contentType === 'html' ? notification.content : `<pre>${notification.content}</pre>`
    );
    
    if (result.success) {
      await markNotificationAsSent(`generic/${notificationId}`);
    }
  });
}

// Start monitoring
function startMonitoring() {
  console.log('🚀 Starting database monitoring for email notifications...');
  
  startRecipientsWatcher();
  monitorWaterLeakNotifications();
  monitorManualActivitiesNotifications();
  monitorGenericNotifications();
  monitorRealtimeLeakAlerts();
  monitorReportEmails();
  
  console.log('✅ All monitors started successfully!');
}

// Start the monitoring service
startMonitoring();

module.exports = {
  sendEmail,
  markNotificationAsSent,
  emailTemplates
};

